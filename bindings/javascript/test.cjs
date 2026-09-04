"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  assertLatticeProvider,
  assertScalarWfstProvider,
  assertSemiringProvider,
  normalizeLatticeProviderOptions,
  normalizeScalarWfstProviderOptions,
  normalizeSemiringProviderOptions,
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

test("CommonJS validates lattice and semiring providers", () => {
  const lattice = {
    join: () => lattice,
    meet: () => lattice,
    equal: () => true,
    diagnostic: () => "maximum(3)",
  };
  const semiring = {
    zero: () => Infinity,
    one: () => 0,
    plus: Math.min,
    times: (left, right) => left + right,
    equal: Object.is,
    approximatelyEqual: (left, right, epsilon) => Math.abs(left - right) <= epsilon,
    naturalOrder: () => "equal",
    diagnostic: String,
  };
  assert.doesNotThrow(() => assertLatticeProvider(lattice));
  assert.doesNotThrow(() => assertSemiringProvider(semiring));
  assert.deepEqual(normalizeLatticeProviderOptions({ domainId: "example.domain.1" }), {
    domainId: "example.domain.1",
  });
  assert.deepEqual(normalizeSemiringProviderOptions({ domainId: "demo.semiring.01" }), {
    domainId: "demo.semiring.01",
    properties: [],
    closureBound: null,
  });
});
