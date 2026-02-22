/** @type {import('ts-jest').JestConfigWithTsJest} */
export default {
  preset: "ts-jest/presets/default-esm",
  testEnvironment: "node",
  extensionsToTreatAsEsm: [".ts"],
  moduleNameMapper: {
    "^(\\.{1,2}/.*)\\.js$": "$1",
  },
  transform: {
    "^.+\\.tsx?$": [
      "ts-jest",
      { useESM: true, tsconfig: "tsconfig.json", diagnostics: false },
    ],
    // Transform @aztec ESM packages for Jest
    "^.+\\.js$": [
      "ts-jest",
      { useESM: true, diagnostics: false },
    ],
  },
  // Allow @aztec ESM packages to be transformed by Jest
  transformIgnorePatterns: [
    "node_modules/(?!(@aztec)/)",
  ],
  testMatch: ["**/test/**/*.test.ts"],
  testTimeout: 300_000,
};
