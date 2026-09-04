"use strict";

function assertSameRuntime(resource, expected) {
  if (resource == null || resource.runtimeIdentity !== expected) {
    throw new TypeError("resource belongs to a different Vinary Tree runtime");
  }
}

function assertDictionaryResource(resource) {
  if (resource == null || resource.interfaceId !== "vt.dictionary.v1") {
    throw new TypeError("resource does not implement vt.dictionary.v1");
  }
}

function assertWfstResource(resource) {
  if (resource == null || resource.interfaceId !== "vt.scalar-wfst.1") {
    throw new TypeError("resource does not implement vt.scalar-wfst.1");
  }
}

function assertLatticeResource(resource) {
  if (resource == null || resource.interfaceId !== "vt.lattice.val.1") {
    throw new TypeError("resource does not implement vt.lattice.val.1");
  }
}

function assertSemiringResource(resource) {
  if (resource == null || resource.interfaceId !== "vt.semiring.val1") {
    throw new TypeError("resource does not implement vt.semiring.val1");
  }
}

function assertProviderObject(provider, name) {
  if (provider == null || typeof provider !== "object" || Array.isArray(provider)) {
    throw new TypeError(`${name} provider must be an object`);
  }
}

function assertRequiredMethods(provider, name, methods) {
  for (const method of methods) {
    if (typeof provider[method] !== "function") {
      throw new TypeError(`${name} provider is missing ${method}()`);
    }
  }
}

function assertOptionalMethodGroup(provider, name, methods) {
  const present = methods.filter((method) => provider[method] !== undefined);
  if (present.length === 0) return;
  if (present.length !== methods.length || methods.some((method) => typeof provider[method] !== "function")) {
    throw new TypeError(`${name} provider must implement ${methods.join("() and ")}() together`);
  }
}

function assertScalarWfstProvider(provider) {
  assertProviderObject(provider, "scalar WFST");
  assertRequiredMethods(provider, "scalar WFST", ["startState", "stateCount", "stateInfo", "stateArcs"]);
  if (provider.stateArcsPage !== undefined && typeof provider.stateArcsPage !== "function") {
    throw new TypeError("scalar WFST provider stateArcsPage must be a function when present");
  }
}

function assertLatticeProvider(provider) {
  assertProviderObject(provider, "lattice");
  assertRequiredMethods(provider, "lattice", ["join", "meet", "equal", "diagnostic"]);
  if (provider.stableBytes !== undefined && typeof provider.stableBytes !== "function") {
    throw new TypeError("lattice provider stableBytes must be a function when present");
  }
  assertOptionalMethodGroup(provider, "lattice", ["joinMany", "meetMany"]);
}

function assertSemiringProvider(provider) {
  assertProviderObject(provider, "semiring");
  assertRequiredMethods(provider, "semiring", [
    "zero", "one", "plus", "times", "equal", "approximatelyEqual", "naturalOrder", "diagnostic",
  ]);
  if (provider.stableBytes !== undefined && typeof provider.stableBytes !== "function") {
    throw new TypeError("semiring provider stableBytes must be a function when present");
  }
  if (provider.star !== undefined && typeof provider.star !== "function") {
    throw new TypeError("semiring provider star must be a function when present");
  }
  assertOptionalMethodGroup(provider, "semiring", ["plusMany", "timesMany"]);
  assertOptionalMethodGroup(provider, "semiring", ["divide", "leftDivide"]);
  assertOptionalMethodGroup(provider, "semiring", ["numericalValue", "quantize", "toProbability"]);
}

const unitDomains = new Set(["byte", "unicode", "u64"]);
const weightDomains = new Set([
  "tropical-f64",
  "log-f64",
  "probability-f64",
  "arctic-f64",
  "signed-tropical-f64",
  "count-f64",
  "boolean-f64",
]);

const semiringProperties = new Set([
  "hashable",
  "idempotent-plus",
  "k-closed",
  "zero-sum-free",
  "commutative-times",
  "totally-ordered",
  "nonnegative",
]);

function normalizeProviderOptions(options, name) {
  if (options === null || typeof options !== "object" || Array.isArray(options)) {
    throw new TypeError(`${name} provider options must be an object`);
  }
  const domainId = options.domainId;
  if (typeof domainId !== "string" || domainId.length !== 16 || !/^[\x20-\x7e]{16}$/.test(domainId)) {
    throw new TypeError(`${name} domainId must contain exactly 16 printable ASCII characters`);
  }
  return domainId;
}

function normalizeScalarWfstProviderOptions(options = {}) {
  if (options === null || typeof options !== "object" || Array.isArray(options)) {
    throw new TypeError("scalar WFST provider options must be an object");
  }
  const unitDomain = options.unitDomain ?? "unicode";
  if (!unitDomains.has(unitDomain)) throw new RangeError(`unknown unit domain ${unitDomain}`);
  const weightDomain = options.weightDomain ?? "tropical-f64";
  if (!weightDomains.has(weightDomain)) {
    throw new RangeError(`unknown weight domain ${weightDomain}`);
  }
  const lazy = options.lazy ?? true;
  const acyclic = options.acyclic ?? false;
  if (typeof lazy !== "boolean") throw new TypeError("lazy must be boolean");
  if (typeof acyclic !== "boolean") throw new TypeError("acyclic must be boolean");
  return Object.freeze({ unitDomain, weightDomain, lazy, acyclic });
}

function normalizeLatticeProviderOptions(options) {
  const domainId = normalizeProviderOptions(options, "lattice");
  return Object.freeze({ domainId });
}

function normalizeSemiringProviderOptions(options) {
  const domainId = normalizeProviderOptions(options, "semiring");
  const inputProperties = options.properties ?? [];
  if (!Array.isArray(inputProperties)) {
    throw new TypeError("semiring properties must be an array");
  }
  const properties = [...new Set(inputProperties)];
  for (const property of properties) {
    if (!semiringProperties.has(property)) {
      throw new RangeError(`unknown semiring property ${property}`);
    }
  }
  properties.sort();
  const closureBound = options.closureBound ?? null;
  if (closureBound !== null &&
      (typeof closureBound !== "bigint" || closureBound < 0n || closureBound > 0xffff_ffff_ffff_ffffn)) {
    throw new RangeError("semiring closureBound must be null or an unsigned 64-bit bigint");
  }
  if (closureBound !== null && !properties.includes("k-closed")) {
    throw new RangeError("semiring closureBound requires the k-closed property");
  }
  return Object.freeze({
    domainId,
    properties: Object.freeze(properties),
    closureBound,
  });
}

module.exports = {
  assertSameRuntime,
  assertDictionaryResource,
  assertWfstResource,
  assertLatticeResource,
  assertSemiringResource,
  assertScalarWfstProvider,
  assertLatticeProvider,
  assertSemiringProvider,
  normalizeScalarWfstProviderOptions,
  normalizeLatticeProviderOptions,
  normalizeSemiringProviderOptions,
};
