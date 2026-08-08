///|
/// Provider factory that selects models and provider-level services.
///
/// This is the MoonBit counterpart of AI SDK's `ProviderV4`. Language,
/// embedding, and image selectors are required by that contract and raise
/// `NoSuchModelError` when unsupported. Optional TypeScript members are
/// represented as nullable results because MoonBit traits are nominal.
pub(open) trait ProviderV4 {
  fn specification_version(Self) -> String
  fn language_model(Self, String) -> &LanguageModelV4 raise
  fn embedding_model(Self, String) -> &EmbeddingModelV4 raise
  fn image_model(Self, String) -> &ImageModelV4 raise
  fn transcription_model(Self, String) -> &TranscriptionModelV4? raise
  fn speech_model(Self, String) -> &SpeechModelV4? raise
  fn reranking_model(Self, String) -> &RerankingModelV4? raise
  fn files(Self) -> &FilesV4? raise
  fn skills(Self) -> &SkillsV4? raise
}

///|
/// Normalized protocol interface used inside provider wire adapters.
///
/// Provider factories expose `LanguageModelV4` to callers. `ChatModel` exists
/// for protocol reuse and explicit third-party adaptation only.
pub(open) trait ChatModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  fn supported_urls(Self) -> Array[SupportedUrlRule]
  async fn generate(Self, ChatCallOptions) -> ChatResponse
  async fn stream(Self, ChatCallOptions, async (StreamEvent) -> Unit) -> ChatResponse
}

///|
/// Protocol-level embedding model used by concrete wire adapters.
///
/// High-level callers use `EmbeddingModelV4`; this trait isolates endpoint
/// request and response types from the versioned provider contract.
pub(open) trait EmbeddingWireModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  fn max_embeddings_per_call(Self) -> Int
  /// Whether separate embedding batches may be in flight at the same time.
  ///
  /// Providers that serialize or rate-limit embedding requests should return
  /// `false`; the high-level `embed_many` helper will then preserve ordering
  /// while executing batches sequentially.
  fn supports_parallel_calls(Self) -> Bool
  async fn embed(Self, Array[String], EmbeddingOptions) -> EmbeddingBatchResponse
}

///|
/// Provider-neutral V4 reranking model.
pub(open) trait RerankingModelV4 {
  fn specification_version(Self) -> String
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn do_rerank(Self, RerankingModelV4CallOptions) -> RerankingModelV4Result
}

///|
/// Protocol-level model for OpenAI-style legacy `/completions` endpoints.
pub(open) trait CompletionModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn generate(Self, CompletionOptions) -> CompletionResponse
  async fn stream(Self, CompletionOptions, async (StreamEvent) -> Unit) -> CompletionResponse
}

///|
/// Protocol-level image model used by concrete wire adapters.
///
/// High-level callers use `ImageModelV4`. This trait only exists so a provider
/// can keep its endpoint encoder/decoder isolated from the versioned contract.
pub(open) trait ImageWireModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  fn max_images_per_call(Self) -> Int
  async fn generate(Self, ImageCallOptions) -> ImageResponse
}

///|
/// Protocol-level video model used by the migration adapter.
///
/// High-level callers use `VideoModelV4`; this contract keeps the existing
/// request/response shape available only to provider wire implementations.
pub(open) trait VideoWireModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  fn max_videos_per_call(Self) -> Int
  async fn generate(Self, VideoCallOptions) -> VideoResponse
}

///|
/// Provider-neutral interface for uploading files and receiving reusable
/// provider references.
pub(open) trait FilesV4 {
  fn specification_version(Self) -> String
  fn provider(Self) -> String
  async fn upload_file(Self, FilesV4UploadFileCallOptions) -> FilesV4UploadFileResult
}

///|
/// Protocol-level text-to-speech model used by migration adapters.
///
/// High-level callers use `SpeechModelV4`.
pub(open) trait SpeechWireModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn generate(Self, SpeechCallOptions) -> SpeechResponse
}

///|
/// Protocol-level transcription model used by migration adapters.
///
/// High-level callers use `TranscriptionModelV4`.
pub(open) trait TranscriptionWireModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn generate(Self, TranscriptionCallOptions) -> TranscriptionResponse
  async fn stream(
    Self,
    TranscriptionStreamOptions,
    async (TranscriptionStreamEvent) -> Unit,
  ) -> TranscriptionResponse
}

///|
/// Protocol-level streaming speech translation model used by migration
/// adapters. High-level callers use `SpeechTranslationModelV4`.
pub(open) trait SpeechTranslationWireModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn stream(
    Self,
    SpeechTranslationCallOptions,
    async (SpeechTranslationStreamEvent) -> Unit,
  ) -> SpeechTranslationResponse
}

///|
/// Protocol-level realtime adapter retained for explicit migration code.
/// Session state and transport ownership live above `RealtimeModelV4`.
pub(open) trait RealtimeWireModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn do_create_client_secret(Self, RealtimeClientSecretOptions) -> RealtimeClientSecretResult
  fn get_websocket_config(Self, String, String) -> RealtimeWebSocketConfig
  fn parse_server_event(Self, Json) -> Array[RealtimeServerEvent]
  fn serialize_client_event(Self, RealtimeClientEvent) -> Json
  fn build_session_config(Self, RealtimeSessionConfig) -> Json
}

///|
/// Provider-neutral interface for uploading reusable skill bundles.
pub(open) trait SkillsV4 {
  fn specification_version(Self) -> String
  fn provider(Self) -> String
  async fn upload_skill(Self, SkillsV4UploadSkillCallOptions) -> SkillsV4UploadSkillResult
}
