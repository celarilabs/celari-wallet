#!/usr/bin/env node
/**
 * Extension build script using esbuild.
 *
 * Two build passes:
 *  1. Standard (bundle: false) — background, content, inpage, popup
 *  2. Bundled (bundle: true)   — offscreen.js with full Aztec SDK for WASM PXE
 *
 * Usage:
 *   node extension/build.mjs          # production build
 *   node extension/build.mjs --dev    # development build with sourcemaps
 */

import { build } from "esbuild";
import { cpSync, mkdirSync, existsSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const isDev = process.argv.includes("--dev");
const rootDir = resolve(__dirname, "..");

const outdir = resolve(__dirname, "dist");

// Ensure output directory exists
mkdirSync(outdir, { recursive: true });
mkdirSync(resolve(outdir, "src/pages"), { recursive: true });
mkdirSync(resolve(outdir, "styles"), { recursive: true });
mkdirSync(resolve(outdir, "icons"), { recursive: true });
mkdirSync(resolve(outdir, "fonts"), { recursive: true });
mkdirSync(resolve(outdir, "wasm"), { recursive: true });

// --- Pass 1: Standard entry points (no bundling) ---

const entryPoints = [
  { in: resolve(__dirname, "public/src/background.js"), out: "src/background" },
  { in: resolve(__dirname, "public/src/content.js"), out: "src/content" },
  { in: resolve(__dirname, "public/src/inpage.js"), out: "src/inpage" },
  { in: resolve(__dirname, "public/src/pages/popup.js"), out: "src/pages/popup" },
];

try {
  await build({
    entryPoints: entryPoints.map(e => ({ in: e.in, out: e.out })),
    bundle: false,        // No bundling needed (no imports between files)
    minify: !isDev,
    sourcemap: isDev,
    outdir,
    format: "esm",
    target: ["chrome120"],
    logLevel: "info",
    ...(isDev ? {} : { drop: ["console"], define: { "process.env.NODE_ENV": '"production"' } }),
  });

  console.log("  Pass 1: Standard entry points OK");

  // --- Pass 2: Offscreen bundle (Aztec SDK + WASM PXE) ---

  console.log("  Pass 2: Bundling offscreen.js with Aztec SDK...");

  await build({
    entryPoints: [
      { in: resolve(__dirname, "public/src/offscreen.js"), out: "src/offscreen" },
    ],
    bundle: true,
    minify: !isDev,
    sourcemap: isDev,
    outdir,
    format: "esm",
    target: ["chrome120"],
    platform: "browser",
    conditions: ["browser", "module"],
    logLevel: "info",
    ...(isDev ? {} : { drop: ["console"] }),
    define: {
      "process.env.NODE_ENV": JSON.stringify(isDev ? "development" : "production"),
      "process.env.PXE_PROVER_ENABLED": '"true"',
      "process.env.PXE_L2_BLOCK_BATCH_SIZE": '"50"',
      "process.env.NETWORK": '""',
      "process.env.BB_SKIP_CLEANUP": '""',
      "process.env.DATA_DIRECTORY": '""',
      "process.env.DATA_URL": '""',
      "global": "globalThis",
    },
    // Resolve Node.js built-ins to browser polyfills/shims
    alias: {
      "crypto": resolve(__dirname, "shims/crypto-shim.js"),
      "assert": resolve(__dirname, "shims/assert-shim.js"),
      "tty": resolve(__dirname, "shims/empty-shim.js"),
      "net": resolve(__dirname, "shims/empty-shim.js"),
      "fs": resolve(__dirname, "shims/empty-shim.js"),
      "os": resolve(__dirname, "shims/empty-shim.js"),
      "child_process": resolve(__dirname, "shims/empty-shim.js"),
      "path": resolve(rootDir, "node_modules/path-browserify"),
      "stream": resolve(rootDir, "node_modules/stream-browserify"),
      "util": resolve(rootDir, "node_modules/util"),
      "buffer": resolve(rootDir, "node_modules/buffer"),
      "events": resolve(rootDir, "node_modules/events"),
    },
    external: [],
    loader: {
      ".wasm": "file",  // Copy WASM files and return URL
    },
    // Allow JSON imports (contract artifact)
    resolveExtensions: [".js", ".ts", ".json"],
  });

  console.log("  Pass 2: Offscreen bundle OK");

  // --- Pass 3: iOS offscreen bundle (ESM — WKWebView Safari 17+ supports modules) ---
  // IMPORTANT: Previous IIFE format caused `import.meta` to be replaced with `{}`,
  // breaking WASM loading (acvm_js, noirc_abi) and Worker URLs (Barretenberg).
  // ESM format preserves `import.meta.url` so `new URL("file.wasm", import.meta.url)` works.

  if (process.argv.includes("--ios") || process.argv.includes("--all")) {
    const iosOutdir = resolve(__dirname, "..", "ios/CelariWallet/CelariWallet/Resources");
    console.log("  Pass 3: Bundling offscreen.js for iOS (ESM format)...");

    await build({
      entryPoints: [
        { in: resolve(__dirname, "public/src/offscreen.js"), out: "offscreen" },
      ],
      bundle: true,
      minify: true,
      sourcemap: false,
      outdir: iosOutdir,
      format: "esm",
      target: ["safari17"],
      platform: "browser",
      conditions: ["browser", "module"],
      logLevel: "info",
      define: {
        "process.env.NODE_ENV": '"production"',
        "process.env.PXE_PROVER_ENABLED": '"true"',
        "process.env.PXE_L2_BLOCK_BATCH_SIZE": '"50"',
        "process.env.NETWORK": '""',
        "process.env.BB_SKIP_CLEANUP": '""',
        "process.env.DATA_DIRECTORY": '""',
        "process.env.DATA_URL": '""',
        "global": "globalThis",
        "process.browser": "true",
      },
      alias: {
        "crypto": resolve(__dirname, "shims/crypto-shim.js"),
        "assert": resolve(__dirname, "shims/assert-shim.js"),
        "tty": resolve(__dirname, "shims/empty-shim.js"),
        "net": resolve(__dirname, "shims/empty-shim.js"),
        "fs": resolve(__dirname, "shims/empty-shim.js"),
        "os": resolve(__dirname, "shims/empty-shim.js"),
        "child_process": resolve(__dirname, "shims/empty-shim.js"),
        "path": resolve(rootDir, "node_modules/path-browserify"),
        "stream": resolve(rootDir, "node_modules/stream-browserify"),
        "util": resolve(rootDir, "node_modules/util"),
        "buffer": resolve(rootDir, "node_modules/buffer"),
        "events": resolve(rootDir, "node_modules/events"),
      },
      external: [],
      loader: {
        ".wasm": "file",  // Emit WASM files alongside JS (import.meta.url resolves correctly in ESM)
      },
      resolveExtensions: [".js", ".ts", ".json"],
    });

    console.log("  Pass 3: iOS offscreen bundle OK → " + iosOutdir);
  }

  // --- Copy WASM files to dist/wasm/ ---

  const wasmSources = [
    { src: "node_modules/@aztec/noir-acvm_js/web/acvm_js_bg.wasm", name: "acvm_js_bg.wasm" },
    { src: "node_modules/@aztec/noir-noirc_abi/web/noirc_abi_wasm_bg.wasm", name: "noirc_abi_wasm_bg.wasm" },
  ];

  for (const w of wasmSources) {
    const srcPath = resolve(rootDir, w.src);
    if (existsSync(srcPath)) {
      cpSync(srcPath, resolve(outdir, "wasm", w.name));
      console.log(`  WASM: ${w.name} copied`);
    } else {
      console.warn(`  WASM: ${w.name} not found at ${srcPath}`);
    }
  }

  // --- Copy static assets ---

  cpSync(resolve(__dirname, "public/manifest.json"), resolve(outdir, "manifest.json"));
  cpSync(resolve(__dirname, "public/popup.html"), resolve(outdir, "popup.html"));
  cpSync(resolve(__dirname, "public/sidepanel.html"), resolve(outdir, "sidepanel.html"));
  cpSync(resolve(__dirname, "public/offscreen.html"), resolve(outdir, "offscreen.html"));
  cpSync(resolve(__dirname, "public/styles"), resolve(outdir, "styles"), { recursive: true });
  cpSync(resolve(__dirname, "public/icons"), resolve(outdir, "icons"), { recursive: true });
  if (existsSync(resolve(__dirname, "public/fonts"))) {
    cpSync(resolve(__dirname, "public/fonts"), resolve(outdir, "fonts"), { recursive: true });
  }

  console.log(`\n✅ Extension built → extension/dist/ (${isDev ? "dev" : "production"})`);
} catch (e) {
  console.error("Build failed:", e.message);
  if (e.errors) {
    for (const err of e.errors.slice(0, 10)) {
      console.error(`  ${err.location?.file}:${err.location?.line} — ${err.text}`);
    }
  }
  process.exit(1);
}
