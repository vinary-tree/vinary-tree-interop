import assert from "node:assert/strict";
import test from "node:test";

import {
  assertDictionaryResource,
  assertLatticeProvider,
  assertLatticeResource,
  assertSameRuntime,
  assertScalarWfstProvider,
  assertSemiringProvider,
  assertSemiringResource,
  assertWfstResource,
  normalizeLatticeProviderOptions,
  normalizeScalarWfstProviderOptions,
  normalizeSemiringProviderOptions,
} from "./index.mjs";

test("runtime identity prevents cross-instance handles", () => {
  const runtimeIdentity = {};
  const resource = {
    runtimeIdentity,
    interfaceId: "vt.dictionary.v1",
    unitDomain: "unicode",
    valueDomain: "optional-u64",
    close() {},
  };
  assert.doesNotThrow(() => assertSameRuntime(resource, runtimeIdentity));
  assert.throws(() => assertSameRuntime(resource, {}), /different/);
  assert.doesNotThrow(() => assertDictionaryResource(resource));
  assert.throws(
    () => assertDictionaryResource({ ...resource, interfaceId: "vt.dictionary.v2" }),
    /vt\.dictionary\.v1/,
  );
});

test("scalar WFST resources are independently versioned", () => {
  const resource = {
    runtimeIdentity: {},
    interfaceId: "vt.scalar-wfst.1",
    weightDomain: "tropical-f64",
    close() {},
  };
  assert.doesNotThrow(() => assertWfstResource(resource));
  assert.throws(
    () => assertWfstResource({ ...resource, interfaceId: "vt.scalar-wfst.2" }),
    /vt\.scalar-wfst\.1/,
  );
  assert.throws(() => assertDictionaryResource(resource), /vt\.dictionary\.v1/);
});

test("lattice and semiring resources retain distinct negotiated identities", () => {
  const base = { runtimeIdentity: {}, domainId: "example.domain.1", close() {} };
  const lattice = { ...base, interfaceId: "vt.lattice.val.1" };
  const semiring = { ...base, interfaceId: "vt.semiring.val1" };
  assert.doesNotThrow(() => assertLatticeResource(lattice));
  assert.doesNotThrow(() => assertSemiringResource(semiring));
  assert.throws(() => assertLatticeResource(semiring), /vt\.lattice\.val\.1/);
  assert.throws(() => assertSemiringResource(lattice), /vt\.semiring\.val1/);
});

test("scalar WFST provider validation is structural and fail closed", () => {
  const provider = {
    startState: () => 0n,
    stateCount: () => 1n,
    stateInfo: () => ({ valid: true, final: true, finalWeight: 0 }),
    stateArcs: () => [],
    stateArcsPage: () => ({ arcs: [], total: 0n }),
  };
  assert.doesNotThrow(() => assertScalarWfstProvider(provider));
  assert.throws(() => assertScalarWfstProvider(null), /must be an object/);
  assert.throws(() => assertScalarWfstProvider({ ...provider, stateInfo: null }), /stateInfo/);
  assert.throws(() => assertScalarWfstProvider({ ...provider, stateArcsPage: 7 }), /stateArcsPage/);
  assert.throws(() => assertScalarWfstProvider([]), /must be an object/);
});

test("scalar WFST provider options have one validated cross-runtime normalization", () => {
  assert.deepEqual(normalizeScalarWfstProviderOptions(), {
    unitDomain: "unicode",
    weightDomain: "tropical-f64",
    lazy: true,
    acyclic: false,
  });
  assert.equal(Object.isFrozen(normalizeScalarWfstProviderOptions()), true);
  assert.deepEqual(normalizeScalarWfstProviderOptions({
    unitDomain: "u64",
    weightDomain: "boolean-f64",
    lazy: false,
    acyclic: true,
  }), {
    unitDomain: "u64",
    weightDomain: "boolean-f64",
    lazy: false,
    acyclic: true,
  });
  assert.throws(() => normalizeScalarWfstProviderOptions(null), /must be an object/);
  assert.throws(() => normalizeScalarWfstProviderOptions({ unitDomain: "utf16" }), /unit domain/);
  assert.throws(() => normalizeScalarWfstProviderOptions({ weightDomain: "mystery" }), /weight domain/);
  assert.throws(() => normalizeScalarWfstProviderOptions({ lazy: 1 }), /lazy must be boolean/);
});

test("lattice provider validation requires coherent optional batches", () => {
  const provider = {
    join: () => provider,
    meet: () => provider,
    equal: () => true,
    diagnostic: () => "maximum(3)",
    stableBytes: () => new Uint8Array([3]),
    joinMany: () => provider,
    meetMany: () => provider,
  };
  assert.doesNotThrow(() => assertLatticeProvider(provider));
  assert.throws(() => assertLatticeProvider({ ...provider, equal: null }), /equal/);
  assert.throws(() => assertLatticeProvider({ ...provider, meetMany: undefined }), /together/);
  assert.deepEqual(normalizeLatticeProviderOptions({ domainId: "example.domain.1" }), {
    domainId: "example.domain.1",
  });
  assert.throws(() => normalizeLatticeProviderOptions({ domainId: "short" }), /16 printable/);
});

test("semiring provider validation keeps optional capability groups sound", () => {
  const provider = {
    zero: () => Infinity,
    one: () => 0,
    plus: Math.min,
    times: (left, right) => left + right,
    equal: Object.is,
    approximatelyEqual: (left, right, epsilon) => Math.abs(left - right) <= epsilon,
    naturalOrder: (left, right) => left < right ? "better" : left > right ? "worse" : "equal",
    diagnostic: String,
    stableBytes: (value) => new TextEncoder().encode(String(value)),
    plusMany: (values) => Math.min(...values),
    timesMany: (values) => values.reduce((sum, value) => sum + value, 0),
    divide: (left, right) => left - right,
    leftDivide: (left, right) => left - right,
    star: (value) => value >= 0 ? 0 : null,
    numericalValue: Number,
    quantize: (value, epsilon) => BigInt(Math.round(value / epsilon)),
    toProbability: (value) => Math.exp(-value),
  };
  assert.doesNotThrow(() => assertSemiringProvider(provider));
  assert.throws(() => assertSemiringProvider({ ...provider, leftDivide: undefined }), /together/);
  assert.throws(() => assertSemiringProvider({ ...provider, toProbability: undefined }), /together/);
  const options = normalizeSemiringProviderOptions({
    domainId: "demo.semiring.01",
    properties: ["totally-ordered", "idempotent-plus", "totally-ordered"],
    closureBound: null,
  });
  assert.deepEqual(options, {
    domainId: "demo.semiring.01",
    properties: ["idempotent-plus", "totally-ordered"],
    closureBound: null,
  });
  assert.equal(Object.isFrozen(options), true);
  assert.equal(Object.isFrozen(options.properties), true);
  assert.throws(
    () => normalizeSemiringProviderOptions({ domainId: "demo.semiring.01", closureBound: 4n }),
    /k-closed/,
  );
  assert.throws(
    () => normalizeSemiringProviderOptions({ domainId: "demo.semiring.01", properties: ["field"] }),
    /unknown semiring property/,
  );
});
