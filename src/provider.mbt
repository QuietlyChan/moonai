///|
/// Common interface implemented by every language model provider package.
pub(open) trait ChatModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn generate(Self, ChatCallOptions) -> ChatResponse
  async fn stream(Self, ChatCallOptions, async (StreamEvent) -> Unit) -> ChatResponse
}

///|
/// Provider-neutral text embedding model.
pub(open) trait EmbeddingModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  fn max_embeddings_per_call(Self) -> Int
  async fn embed(Self, Array[String], EmbeddingOptions) -> EmbeddingBatchResponse
}

///|
/// Provider-neutral legacy text completion model.
pub(open) trait CompletionModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn generate(Self, CompletionOptions) -> CompletionResponse
  async fn stream(Self, CompletionOptions, async (StreamEvent) -> Unit) -> CompletionResponse
}

///|
/// Provider-neutral image generation model.
pub(open) trait ImageModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  fn max_images_per_call(Self) -> Int
  async fn generate(Self, ImageCallOptions) -> ImageResponse
}
