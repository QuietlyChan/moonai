///|
/// Cerebras chat model ids (https://inference-docs.cerebras.ai/models/overview).
pub type CerebrasChatModelId = String

///|
/// Provider options accepted under the `cerebras` namespace (all optional):
///
/// - `user` (string): end-user identifier.
/// - `strictJsonSchema` (bool): enforce strict JSON schema validation.
/// - `parallelToolCalls` (bool): run tool calls in parallel.
/// - `logprobs` (bool): return log probabilities.
/// - `topLogprobs` (int, 0-20): number of top log probabilities per token.
/// - `logitBias` (map): token bias values between -100 and 100.
/// - `serviceTier` (string): `"auto" | "default" | "flex" | "priority"`.
/// - `reasoningEffort` (string): `"none" | "low" | "medium" | "high"`.
/// - `reasoningFormat` (string): `"none" | "parsed" | "text_parsed" | "raw" |
///   "hidden"`.
/// - `prediction` (object): `{ type: "content", content }` predicted output.
/// - `promptCacheKey` (string, <=1024 chars): prompt cache key.
