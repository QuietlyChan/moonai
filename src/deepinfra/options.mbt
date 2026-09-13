///|
/// DeepInfra chat model ids (https://deepinfra.com/models/text-generation).
pub type DeepInfraChatModelId = String

///|
/// DeepInfra completion model ids share the chat model id space.
pub type DeepInfraCompletionModelId = String

///|
/// DeepInfra embedding model ids (https://deepinfra.com/models/embeddings).
pub type DeepInfraEmbeddingModelId = String

///|
/// DeepInfra image model ids (https://deepinfra.com/models/text-to-image).
pub type DeepInfraImageModelId = String

///|
/// Provider options accepted under the `deepinfra` namespace for image
/// generation (all optional, wire names as given): `negative_prompt`,
/// `num_inference_steps`, `guidance_scale`, `guidance`, `response_format`
/// (`"b64_json"`), `quality`, `style`, `user`.
