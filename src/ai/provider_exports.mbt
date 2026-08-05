///|
/// Import provider contracts for the high-level AI implementation. Consumers
/// import `QuietlyChan/moonai/provider` when they need protocol types.
using @provider {
  check_cancellation,
  copy_provider_metadata,
  copy_warnings,
  merge_optional_response_metadata,
  merge_provider_metadata,
  type AudioFormat,
  type CancellationToken,
  type CompletionOptions,
  type CompletionResponse,
  type EmbeddingBatchResponse,
  type EmbeddingResponse,
  type FileUploadOptions,
  type FileUploadResult,
  type GeneratedImage,
  type ImageResponse,
  type RealtimeClientSecretOptions,
  type RealtimeClientSecretResult,
  type ReasoningEffort,
  type RequestMetadata,
  type RerankingCallOptions,
  type RerankingDocuments,
  type ResponseFormat,
  type ResponseMetadata,
  type RetryPolicy,
  type SkillFile,
  type SkillUploadOptions,
  type SkillUploadResult,
  type SpeechResponse,
  type SpeechTranslationResponse,
  type SpeechTranslationStreamEvent,
  type StreamEvent,
  type ToolChoice,
  type ToolDefinition,
  type TranscriptionAudio,
  type TranscriptionResponse,
  type TranscriptionStreamEvent,
  type UploadFileData,
  type Usage,
  type VideoModelV4CallOptions,
  type VideoModelV4File,
  type VideoModelV4FrameImage,
  type VideoModelV4Result,
  type VideoModelV4VideoData,
  type Warning,
  trait CompletionModel,
  trait Files,
  trait RealtimeModelV4,
  trait RerankingModel,
  trait Skills,
  trait SpeechModelV4,
  trait AudioStream,
  trait SpeechTranslationModelV4,
  trait TranscriptionModelV4,
  trait VideoModelV4,
}

///|
/// User-facing prompt types live in `provider_utils`, matching AI SDK's
/// separation between `ModelMessage` and provider language-model prompts.
pub using @provider_utils {
  type ModelContentPart,
  type ModelMessage,
  type ModelMessageRole,
  type ModelToolCall,
  type ModelToolApprovalRequest,
  type ModelToolApprovalResponse,
  type ModelToolResult,
  type ModelToolResultContentPart,
  type ModelToolResultOutput,
}

///|
/// Prompt conversion is a separate package so providers and future workflows
/// can share URL/file normalization without depending on high-level generation.
pub using @prompt {
  type DownloadFunction,
  type DownloadRequest,
  type DownloadedAsset,
  type Instructions,
  type LanguageModelCallOptions,
  type Prompt,
  type PromptInput,
  type StandardizedPrompt,
}

///|
/// Model identity and registry types are re-exported by the high-level AI
/// package for callers that prefer one import, while the dedicated
/// `ai/model` package remains available for lower-level integrations.
pub using @model {
  parse_model_id,
  model_id_of_language_model,
  type CompletionModelReference,
  type EmbeddingModelReference,
  type EmbeddingModelV4Middleware,
  type EmbeddingModelV4MiddlewareContext,
  type ImageModelReference,
  type InvalidModelIdError,
  type LanguageModelV4Reference,
  type ModelId,
  type ModelRegistry,
  type ModelType,
  type NoSuchModelError,
  type RealtimeModelReference,
  type RerankingModelReference,
  type SpeechModelReference,
  type SpeechTranslationModelReference,
  type TranscriptionModelReference,
  type VideoModelReference,
  type LanguageModelV4Middleware,
  type LanguageModelV4MiddlewareContext,
  type LanguageModelV4MiddlewareOperation,
  type LanguageModelV4TransformContext,
  type ImageModelV4Middleware,
  type ImageModelV4MiddlewareContext,
  wrapLanguageModelV4,
  wrapLanguageModelV4Chain,
  wrap_language_model_v4,
  wrap_language_model_v4_chain,
  wrapEmbeddingModel,
  wrapEmbeddingModelChain,
  wrap_embedding_model_v4,
  wrap_embedding_model_v4_chain,
  wrapImageModel,
  wrapImageModelChain,
  wrapLanguageModel,
  wrapLanguageModelChain,
  asLanguageModelV4,
  as_language_model_v4,
  wrap_image_model_v4,
  wrap_image_model_v4_chain,
}

///|
/// Provider registry types live in a dedicated package because registry
/// resolution depends on provider factories, not on high-level generation.
pub using @registry {
  createProviderRegistry,
  create_provider_registry,
  customProvider,
  custom_provider,
  type CustomProvider,
  type InvalidRegistryModelIdError,
  type NoSuchProviderCapabilityError,
  type NoSuchProviderError,
  type ProviderRegistry,
}
