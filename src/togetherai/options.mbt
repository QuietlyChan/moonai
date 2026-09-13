///|
/// TogetherAI chat model ids (https://docs.together.ai/docs/serverless-models).
pub type TogetherAIChatModelId = String

///|
/// TogetherAI completion model ids
/// (https://docs.together.ai/docs/serverless-models).
pub type TogetherAICompletionModelId = String

///|
/// TogetherAI embedding model ids
/// (https://docs.together.ai/docs/serverless-models).
pub type TogetherAIEmbeddingModelId = String

///|
/// TogetherAI image model ids (https://api.together.ai/models), including the
/// FLUX Kontext editing models.
pub type TogetherAIImageModelId = String

///|
/// TogetherAI reranking model ids (https://docs.together.ai/reference/rerank-1).
pub type TogetherAIRerankingModelId = String

///|
/// Provider options accepted under the `togetherai` namespace for image
/// generation (all optional):
///
/// - `steps` (number): generation steps; higher values can improve quality.
/// - `guidance` (number): guidance scale for image generation.
/// - `negative_prompt` (string): guide what to avoid.
/// - `disable_safety_checker` (bool): skip the NSFW safety checker
///   (unavailable for Flux Schnell Free and Flux Pro models).
///
/// For reranking the namespace accepts `rankFields` (array of strings) to
/// restrict which document fields are ranked.
