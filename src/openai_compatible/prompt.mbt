///|
/// Result of converting provider-neutral messages to an OpenAI-compatible
/// Chat Completions prompt.
///
/// The conversion boundary is intentionally separate from HTTP transport and
/// response decoding: providers such as Alibaba share the wire endpoint but
/// have different content and cache-control semantics.
pub(all) struct OpenAICompatiblePromptConversion {
  messages : Array[Json]
  warnings : Array[@provider.Warning]
}

///|
/// Provider-specific conversion hook for OpenAI-compatible chat prompts.
///
/// `provider_name` is the full model provider name (for example
/// `alibaba.chat`), so a converter can select its own provider-options
/// namespace without coupling the common HTTP model to that package.
pub type OpenAICompatiblePromptConverter = (
  Array[@provider.LanguageModelMessage],
  Bool,
  String,
) -> OpenAICompatiblePromptConversion raise

///|
/// Convert a prompt using the standard OpenAI-compatible message semantics.
pub fn default_openai_compatible_prompt_converter(
  messages : Array[@provider.LanguageModelMessage],
  preserve_reasoning : Bool,
  provider_name : String,
) -> OpenAICompatiblePromptConversion raise {
  let converted : Array[Json] = []
  for message in messages {
    let parts = message_to_json_parts(
      message, preserve_reasoning, provider_name,
    )
    for part in parts {
      converted.push(part)
    }
  }
  { messages: converted, warnings: [] }
}
