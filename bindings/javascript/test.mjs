import assert from "node:assert/strict";
import test from "node:test";

import {
  assertDictionaryResource,
  assertSameRuntime,
  assertScalarWfstProvider,
  assertWfstResource,
  normalizeScalarWfstProviderOptions,
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
