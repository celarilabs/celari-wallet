#!/usr/bin/env node
/**
 * Generate Celari Wallet PNG icons from SVG using Node.js Canvas.
 * Produces icon-16.png, icon-48.png, icon-128.png with Art Deco diamond motif.
 *
 * Requires: npm install canvas (or use sharp if available)
 * Alternative: Uses built-in resvg-js if canvas is unavailable.
 */

import { writeFileSync, mkdirSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const iconsDir = resolve(__dirname, "public/icons");
mkdirSync(iconsDir, { recursive: true });

// Celari logo SVG — Art Deco diamond/keyhole motif
// Colors: Gold (#C9A84C) on dark (#1C1616) background
function generateSVG(size) {
  const pad = Math.round(size * 0.08);
  const s = size;
  const cx = s / 2;
  const cy = s / 2;

  // Scale all elements relative to size
  const hexR = s * 0.42; // hexagon radius
  const circR = s * 0.15; // circle radius
  const dotR = s * 0.055;  // inner dot radius
  const bodyW = s * 0.07; // body width
  const bodyTop = cy + circR * 0.3;
  const bodyBot = cy + hexR * 0.7;

  // Hexagon points
  const hex = [];
  for (let i = 0; i < 6; i++) {
    const angle = (Math.PI / 3) * i - Math.PI / 2;
    hex.push(`${cx + hexR * Math.cos(angle)},${cy + hexR * Math.sin(angle)}`);
  }

  return `<svg xmlns="http://www.w3.org/2000/svg" width="${s}" height="${s}" viewBox="0 0 ${s} ${s}">
  <rect width="${s}" height="${s}" rx="${Math.round(s * 0.15)}" fill="#1C1616"/>
  <polygon points="${hex.join(" ")}" fill="none" stroke="#C9A84C" stroke-width="${Math.max(1, s * 0.015)}" opacity="0.3"/>
  <circle cx="${cx}" cy="${cy - s * 0.08}" r="${circR}" fill="none" stroke="#C9A84C" stroke-width="${Math.max(1, s * 0.02)}"/>
  <circle cx="${cx}" cy="${cy - s * 0.08}" r="${dotR}" fill="#C9A84C"/>
  <path d="M${cx - bodyW} ${bodyTop} L${cx - bodyW * 1.3} ${bodyBot} L${cx} ${bodyBot + s * 0.04} L${cx + bodyW * 1.3} ${bodyBot} L${cx + bodyW} ${bodyTop}" fill="#C9A84C" opacity="0.85"/>
</svg>`;
}

// Try using sharp for SVG → PNG conversion
async function generateWithSharp() {
  const { default: sharp } = await import("sharp");
  const sizes = [16, 48, 128];

  for (const size of sizes) {
    const svg = generateSVG(size);
    const png = await sharp(Buffer.from(svg)).png().toBuffer();
    const outPath = resolve(iconsDir, `icon-${size}.png`);
    writeFileSync(outPath, png);
    console.log(`  icon-${size}.png (${png.length} bytes)`);
  }
}

// Fallback: write SVGs and use resvg-js
async function generateWithResvg() {
  const { Resvg } = await import("@aspect/resvg-js");
  const sizes = [16, 48, 128];

  for (const size of sizes) {
    const svg = generateSVG(size);
    const resvg = new Resvg(svg, { fitTo: { mode: "width", value: size } });
    const png = resvg.render().asPng();
    const outPath = resolve(iconsDir, `icon-${size}.png`);
    writeFileSync(outPath, png);
    console.log(`  icon-${size}.png (${png.length} bytes)`);
  }
}

// Fallback: Use HTML Canvas (canvas package)
async function generateWithCanvas() {
  // This is the simplest approach — just create minimal valid PNGs
  // with a recognizable pattern using raw PNG encoding
  const sizes = [16, 48, 128];

  for (const size of sizes) {
    const svg = generateSVG(size);
    const svgPath = resolve(iconsDir, `icon-${size}.svg`);
    writeFileSync(svgPath, svg);
    console.log(`  icon-${size}.svg written (convert to PNG manually or install sharp)`);
  }
}

// Try available converters in order
console.log("Generating Celari Wallet icons...");
try {
  await generateWithSharp();
  console.log("Done! (using sharp)");
} catch {
  try {
    await generateWithResvg();
    console.log("Done! (using resvg-js)");
  } catch {
    await generateWithCanvas();
    console.log("\nSVG files written. To convert to PNG, run:");
    console.log("  npm install sharp && node extension/generate-icons.mjs");
    console.log("  — or use any SVG to PNG converter");
  }
}
