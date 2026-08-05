///|
/// Native V4 boundary for Anthropic Messages. Files and Skills stay separate
/// capabilities on the provider factory, just like the AI SDK provider.
pub struct AnthropicLanguageModelV4 {
  model : AnthropicMessagesModel
}

///|
/// Construct a V4 Anthropic Messages model.
pub fn AnthropicLanguageModelV4::new(
  model : AnthropicMessagesModel,
) -> AnthropicLanguageModelV4 {
  { model, }
}

///|
pub impl @provider.LanguageModelV4 for AnthropicLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for AnthropicLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider()
}

///|
pub impl @provider.LanguageModelV4 for AnthropicLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id()
}

///|
pub impl @provider.LanguageModelV4 for AnthropicLanguageModelV4 with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.model.supported_urls()
}

///|
pub impl @provider.LanguageModelV4 for AnthropicLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  self.model.generate_v4(options)
}

///|
pub impl @provider.LanguageModelV4 for AnthropicLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  self.model.stream_v4(options, on_event)
}
