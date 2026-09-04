"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  assertScalarWfstProvider,
  normalizeScalarWfstProviderOptions,
} = require("./index.cjs");

test("CommonJS validates scalar WFST providers", () => {
  const provider = {
    startState: () => 0n,
    stateCount: () => 1n,
    stateInfo: () => ({ valid: true, final: true, finalWeight: 0 }),
    stateArcs: () => [],
  };
  assert.doesNotThrow(() => assertScalarWfstProvider(provider));
  assert.throws(
    () => assertScalarWfstProvider({ ...provider, stateArcs: undefined }),
    /stateArcs/,
  );
  assert.deepEqual(normalizeScalarWfstProviderOptions(), {
    unitDomain: "unicode",
    weightDomain: "tropical-f64",
    lazy: true,
    acyclic: false,
  });
});
