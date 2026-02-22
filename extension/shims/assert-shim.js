// Browser shim for Node.js "assert" module
function assert(condition, message) {
  if (!condition) {
    throw new Error(message || "Assertion failed");
  }
}
assert.strict = assert;
assert.ok = assert;
assert.equal = (a, b, msg) => { if (a != b) throw new Error(msg || `${a} != ${b}`); };
assert.strictEqual = (a, b, msg) => { if (a !== b) throw new Error(msg || `${a} !== ${b}`); };
assert.notEqual = (a, b, msg) => { if (a == b) throw new Error(msg || `${a} == ${b}`); };
assert.deepStrictEqual = (a, b, msg) => {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(msg || "Deep strict equal failed");
};
assert.fail = (msg) => { throw new Error(msg || "Assert.fail"); };
export default assert;
export { assert as strict };
