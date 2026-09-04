export function assertSameRuntime(resource, expected) {
  if (resource == null || resource.runtimeIdentity !== expected) {
    throw new TypeError("resource belongs to a different Vinary Tree runtime");
  }
}

export function assertDictionaryResource(resource) {
  if (resource == null || resource.interfaceId !== "vt.dictionary.v1") {
    throw new TypeError("resource does not implement vt.dictionary.v1");
  }
}

export function assertWfstResource(resource) {
  if (resource == null || resource.interfaceId !== "vt.scalar-wfst.1") {
    throw new TypeError("resource does not implement vt.scalar-wfst.1");
  }
}

export function assertScalarWfstProvider(provider) {
  if (provider == null || typeof provider !== "object" || Array.isArray(provider)) {
    throw new TypeError("scalar WFST provider must be an object");
  }
  for (const method of ["startState", "stateCount", "stateInfo", "stateArcs"]) {
    if (typeof provider[method] !== "function") {
      throw new TypeError(`scalar WFST provider is missing ${method}()`);
    }
  }
  if (provider.stateArcsPage !== undefined && typeof provider.stateArcsPage !== "function") {
    throw new TypeError("scalar WFST provider stateArcsPage must be a function when present");
  }
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

export function normalizeScalarWfstProviderOptions(options = {}) {
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
