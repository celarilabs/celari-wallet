/**
 * CORS origin validation for the deploy server.
 * Extracted for testability and reuse.
 */

/** Built-in patterns that are always allowed */
export const CORS_ALLOWED_PATTERNS: RegExp[] = [
  /^chrome-extension:\/\/.+$/,
  /^http:\/\/localhost(:\d+)?$/,
];

/**
 * Read explicit allowed origins from CORS_ORIGIN environment variable.
 * Format: comma-separated list of origins.
 */
export function getAllowedOrigins(): string[] {
  const envOrigins = process.env.CORS_ORIGIN;
  if (envOrigins) {
    return envOrigins.split(",").map((o) => o.trim());
  }
  return [];
}

/**
 * Check if a given origin is allowed by the CORS policy.
 * Checks both the env var whitelist and built-in patterns.
 */
export function isOriginAllowed(origin: string): boolean {
  if (getAllowedOrigins().includes(origin)) return true;
  return CORS_ALLOWED_PATTERNS.some((pattern) => pattern.test(origin));
}
