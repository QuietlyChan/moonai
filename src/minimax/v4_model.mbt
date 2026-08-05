///|
/// MiniMax's V4 language model is backed by its Anthropic-compatible Messages
/// model, while keeping MiniMax's provider identity and options boundary.
pub struct MiniMaxLanguageModelV4 {
  model : MiniMaxChatModel
}

///|
/// Construct a V4 MiniMax model.
pub fn MiniMaxLanguageModelV4::new(
  model : MiniMaxChatModel,
) -> MiniMaxLanguageModelV4 {
  { model, }
}

///|
pub impl @provider.LanguageModelV4 for MiniMaxLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for MiniMaxLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider()
}

///|
pub impl @provider.LanguageModelV4 for MiniMaxLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id()
}

///|
pub impl @provider.LanguageModelV4 for MiniMaxLanguageModelV4 with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.model.supported_urls()
}

///|
pub impl @provider.LanguageModelV4 for MiniMaxLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let model = @anthropic.AnthropicLanguageModelV4::new(self.model)
    as &@provider.LanguageModelV4
  model.do_generate(options)
}

///|
pub impl @provider.LanguageModelV4 for MiniMaxLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let model = @anthropic.AnthropicLanguageModelV4::new(self.model)
    as &@provider.LanguageModelV4
  model.do_stream(options, on_event)
}
