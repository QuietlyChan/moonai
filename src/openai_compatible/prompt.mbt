///|
/// Result of converting a V4 prompt to OpenAI-compatible Chat Completions
/// messages.
///
/// Providers such as Alibaba share the endpoint while retaining their own
/// content and cache-control semantics.
pub(all) struct OpenAICompatiblePromptConversion {
  messages : Array[Json]
  warnings : Array[@provider.Warning]
}

///|
/// Provider-specific conversion hook for a native V4 prompt.
pub type OpenAICompatibleV4PromptConverter = (
  @provider.LanguageModelV4Prompt,
  String,
) -> OpenAICompatiblePromptConversion raise
