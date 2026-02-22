// Empty shim for Node.js built-ins that are not available in browser
// These modules (tty, net, fs, etc.) are referenced by the SDK but never
// actually called in the browser PXE execution path.
export default {};
