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
  type FilesV4UploadFileCallOptions,
  type FilesV4UploadFileResult,
  type GeneratedImage,
  type ImageResponse,
  type RealtimeClientSecretOptions,
  type RealtimeClientSecretResult,
  type ReasoningEffort,
  type RequestMetadata,
  type RerankingModelV4CallOptions,
  type RerankingModelV4Documents,
  type ResponseFormat,
  type ResponseMetadata,
  type RetryPolicy,
  type SkillsV4File,
  type SkillsV4UploadSkillCallOptions,
  type SkillsV4UploadSkillResult,
  type SpeechResponse,
  type SpeechTranslationResponse,
  type SpeechTranslationStreamEvent,
  type StreamEvent,
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
  trait FilesV4,
  trait RealtimeModelV4,
  trait RerankingModelV4,
  trait SkillsV4,
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
  experimentalGetToolCaller,
  experimentalToolCaller,
  experimental_get_tool_caller,
  experimental_tool_caller,
  dynamicTool,
  dynamic_tool,
  isExecutableTool,
  is_executable_tool,
  tool,
  toolSet,
  tool_set,
  type ModelContentPart,
  type ModelMessage,
  type ModelMessageRole,
  type ModelToolCall,
  type ModelToolApprovalRequest,
  type ModelToolApprovalResponse,
  type ModelToolResult,
  type ModelToolResultContentPart,
  type ModelToolResultOutput,
  type ExperimentalSandboxProcess,
  type ExperimentalSandboxSession,
  type SandboxProcess,
  type SandboxSession,
  type Tool,
  type ToolCallerDefinition,
  type ToolDescriptionFunction,
  type ToolDescriptionOptions,
  type ToolExecuteFunction,
  type ToolExecutionOptions,
  type ToolNeedsApproval,
  type ToolNeedsApprovalFunction,
  type ToolNeedsApprovalOptions,
  type ToolSet,
}

///|
/// Caller routing belongs to the high-level generation layer. The dedicated
/// package keeps its preparation algorithm out of provider protocol packages.
pub using @tool {
  type ResolvedToolCallers,
  type ToolCallerConfiguration,
  type ToolCallerReference,
}

///|
/// Text generation owns both non-streaming and streaming multi-step tool
/// workflows in its own package, matching AI SDK's separation from provider
/// protocol contracts.
pub using @generate_text {
  generateText,
  generate_text,
  hasToolCall,
  has_tool_call,
  isLoopFinished,
  isStepCount,
  is_loop_finished,
  is_step_count,
  streamText,
  stream_text,
  type ActiveTools,
  type GenerateTextContent,
  type GenerateTextResult,
  type GenerateTextStep,
  type GenerateTextStepPerformance,
  type GenerateTextToolCall,
  type GenerateTextToolApprovalRequestOutput,
  type GenerateTextToolApprovalResponseOutput,
  type GenerateTextToolResult,
  type GenericToolApprovalFunction,
  type GenericToolApprovalOptions,
  type InvalidToolApprovalError,
  type InvalidToolApprovalSignatureError,
  type InvalidToolInputError,
  type NoSuchToolError,
  type PrepareStepFunction,
  type PrepareStepOptions,
  type PrepareStepResult,
  type StopCondition,
  type StreamTextResult,
  type SingleToolApprovalFunction,
  type SingleToolApprovalOptions,
  type ToolApprovalConfiguration,
  type ToolApprovalRule,
  type ToolApprovalSecret,
  type ToolApprovalStatus,
  type ToolCallNotFoundForApprovalError,
  type ToolOrder,
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
/// Middleware contracts are defined by the provider layer and re-exported by
/// the high-level package, as in AI SDK. Wrapping functions remain in
/// `ai/model`.
pub using @provider {
  type EmbeddingModelV4Middleware,
  type EmbeddingModelV4MiddlewareContext,
  type ImageModelV4Middleware,
  type ImageModelV4MiddlewareContext,
  type LanguageModelV4Middleware,
  type LanguageModelV4MiddlewareContext,
  type LanguageModelV4MiddlewareOperation,
  type LanguageModelV4TransformContext,
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
