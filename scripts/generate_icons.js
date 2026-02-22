/**
 * Generate extension icons as SVG → PNG
 * Run: node scripts/generate_icons.js
 */

import { writeFileSync } from "fs";
import { join, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));

const svgTemplate = (size) => `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 128 128">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#7c3aed"/>
      <stop offset="100%" style="stop-color:#22d3ee"/>
    </linearGradient>
  </defs>
  <rect width="128" height="128" rx="28" fill="url(#bg)"/>
  <text x="64" y="82" text-anchor="middle" font-family="system-ui" font-size="56" font-weight="900" fill="white">Z</text>
  <circle cx="98" cy="30" r="12" fill="#10b981"/>
  <path d="M93 30 L97 34 L103 26" stroke="white" stroke-width="2.5" fill="none" stroke-linecap="round"/>
</svg>`;

[16, 48, 128].forEach((size) => {
  const path = join(__dirname, "..", "extension", "public", "icons", `icon-${size}.svg`);
  writeFileSync(path, svgTemplate(size));
  console.log(`✅ Generated ${path}`);
});

console.log("\nNote: Chrome requires PNG icons. Convert SVGs:");
console.log("  brew install librsvg");
console.log("  rsvg-convert -w 16 icon-16.svg > icon-16.png");
