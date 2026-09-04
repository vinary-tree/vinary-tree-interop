/** Identity of one native, WASM, or WASI umbrella runtime instance. */
export type RuntimeIdentity = symbol | object;

/** Unit domains understood by vt.dictionary.v1. */
export type UnitDomain = "byte" | "unicode" | "u64";

/** Value domains understood by vt.dictionary.v1. */
export type ValueDomain = "unit" | "optional-u64";

/** Base contract implemented by every retained Vinary Tree resource. */
export interface Resource {
  readonly runtimeIdentity: RuntimeIdentity;
  readonly interfaceId: string;
  close(): void;
}

/** Opaque dictionary resource produced by libdictenstein or a host provider. */
export interface DictionaryResource extends Resource {
  readonly interfaceId: "vt.dictionary.v1";
  readonly unitDomain: UnitDomain;
  readonly valueDomain: ValueDomain;
}

/** Scalar semirings supported by vt.scalar-wfst.1. */
export type WeightDomain =
  | "tropical-f64"
  | "log-f64"
  | "probability-f64"
  | "arctic-f64"
  | "signed-tropical-f64"
  | "count-f64"
  | "boolean-f64";

/** Opaque scalar WFST resource produced by lling-llang or duallity. */
export interface WfstResource extends Resource {
  readonly interfaceId: "vt.scalar-wfst.1";
  readonly weightDomain: WeightDomain;
}

/** Stable 16-byte printable-ASCII identity for provider representation and laws. */
export type ProviderDomainId = string;

/** Opaque immutable lattice value carrying the version-1 lattice capability. */
export interface LatticeResource extends Resource {
  readonly interfaceId: "vt.lattice.val.1";
  readonly domainId: ProviderDomainId;
}

/** Opaque dynamic-semiring operation context carrying the version-1 capability. */
export interface SemiringResource extends Resource {
  readonly interfaceId: "vt.semiring.val1";
  readonly domainId: ProviderDomainId;
}

/** Callback-lexical view of a compatible immutable lattice operand. */
export interface LatticeOperand {
  readonly domainId: ProviderDomainId;
  localValue(): LatticeProvider | null;
  stableBytes(): Uint8Array | null;
}

/** One immutable lattice value implemented by JavaScript or TypeScript. */
export interface LatticeProvider {
  join(other: LatticeOperand): LatticeProvider;
  meet(other: LatticeOperand): LatticeProvider;
  equal(other: LatticeOperand): boolean;
  diagnostic(): string;
  stableBytes?(): Uint8Array;
  joinMany?(others: readonly LatticeOperand[]): LatticeProvider;
  meetMany?(others: readonly LatticeOperand[]): LatticeProvider;
}

/** Runtime-neutral semantic identity for a host lattice value. */
export interface LatticeProviderOptions {
  readonly domainId: ProviderDomainId;
}

/** Natural order induced by a semiring's additive operation. */
export type SemiringOrder = "better" | "equal" | "worse" | "incomparable";

/** Optional algebraic laws a semiring provider may claim and validate. */
export type SemiringProperty =
  | "hashable"
  | "idempotent-plus"
  | "k-closed"
  | "zero-sum-free"
  | "commutative-times"
  | "totally-ordered"
  | "nonnegative";

/** Host-defined semiring over immutable JavaScript values. */
export interface SemiringProvider<Value = unknown> {
  zero(): Value;
  one(): Value;
  plus(left: Value, right: Value): Value;
  times(left: Value, right: Value): Value;
  equal(left: Value, right: Value): boolean;
  approximatelyEqual(left: Value, right: Value, epsilon: number): boolean;
  naturalOrder(left: Value, right: Value): SemiringOrder;
  diagnostic(value?: Value): string;
  stableBytes?(value: Value): Uint8Array;
  plusMany?(values: readonly Value[]): Value;
  timesMany?(values: readonly Value[]): Value;
  divide?(dividend: Value, divisor: Value): Value | null;
  leftDivide?(value: Value, divisor: Value): Value | null;
  star?(value: Value): Value | null;
  numericalValue?(value: Value): number;
  quantize?(value: Value, epsilon: number): bigint;
  toProbability?(value: Value): number;
}

/** Runtime-neutral semantic identity and law claims for a host semiring. */
export interface SemiringProviderOptions {
  readonly domainId: ProviderDomainId;
  readonly properties?: readonly SemiringProperty[];
  readonly closureBound?: bigint | null;
}

/** Metadata returned for one provider-scoped scalar-WFST state. */
export interface WfstProviderStateInfo {
  readonly valid: boolean;
  readonly final: boolean;
  readonly finalWeight: number;
}

/** One host-defined scalar-WFST arc; null labels denote epsilon. */
export interface WfstProviderArc {
  readonly input: string | number | bigint | null;
  readonly output: string | number | bigint | null;
  readonly target: bigint;
  readonly weight: number;
}

/** One bounded arc page and the immutable complete outgoing-arc count. */
export interface WfstProviderArcPage {
  readonly arcs: readonly WfstProviderArc[];
  readonly total: bigint;
}

/** Immutable scalar WFST implemented by JavaScript or TypeScript code. */
export interface ScalarWfstProvider {
  startState(): bigint;
  stateCount(): bigint | null;
  stateInfo(state: bigint): WfstProviderStateInfo;
  stateArcs(state: bigint): readonly WfstProviderArc[];
  stateArcsPage?(state: bigint, start: bigint, capacity: number): WfstProviderArcPage;
}

/** Runtime-neutral declaration captured when a host WFST is published. */
export interface ScalarWfstProviderOptions {
  readonly unitDomain?: UnitDomain;
  readonly weightDomain?: WeightDomain;
  readonly lazy?: boolean;
  readonly acyclic?: boolean;
}

/** Rejects handles created by a different native/WASM/WASI runtime instance. */
export function assertSameRuntime(
  resource: Resource,
  expected: RuntimeIdentity,
): void;

/** Narrows a generic resource to the version-1 dictionary interface. */
export function assertDictionaryResource(resource: Resource): asserts resource is DictionaryResource;

/** Narrows a generic resource to the version-1 scalar WFST interface. */
export function assertWfstResource(resource: Resource): asserts resource is WfstResource;

/** Narrows a generic resource to the version-1 lattice interface. */
export function assertLatticeResource(resource: Resource): asserts resource is LatticeResource;

/** Narrows a generic resource to the version-1 dynamic-semiring interface. */
export function assertSemiringResource(resource: Resource): asserts resource is SemiringResource;

/** Validates the structural JavaScript/TypeScript scalar-WFST provider contract. */
export function assertScalarWfstProvider(provider: unknown): asserts provider is ScalarWfstProvider;

/** Validates the structural JavaScript/TypeScript lattice-provider contract. */
export function assertLatticeProvider(provider: unknown): asserts provider is LatticeProvider;

/** Validates the structural JavaScript/TypeScript semiring-provider contract. */
export function assertSemiringProvider(provider: unknown): asserts provider is SemiringProvider;

/** Validates options and fills the runtime-neutral defaults. */
export function normalizeScalarWfstProviderOptions(
  options?: ScalarWfstProviderOptions,
): Readonly<Required<ScalarWfstProviderOptions>>;

/** Validates and freezes one lattice provider's stable semantic identity. */
export function normalizeLatticeProviderOptions(
  options: LatticeProviderOptions,
): Readonly<LatticeProviderOptions>;

/** Validates, canonicalizes, and freezes semiring identity and law claims. */
export function normalizeSemiringProviderOptions(
  options: SemiringProviderOptions,
): Readonly<{
  domainId: ProviderDomainId;
  properties: readonly SemiringProperty[];
  closureBound: bigint | null;
}>;
