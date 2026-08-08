///|
/// The concrete Anthropic model remains package-private. Callers only depend
/// on the shared V4 contract returned by the provider factory.
impl @provider.LanguageModelV4 for AnthropicLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for AnthropicLanguageModel with fn provider(self) -> String {
  self.provider_name
}

///|
impl @provider.LanguageModelV4 for AnthropicLanguageModel with fn model_id(self) -> String {
  self.model_id
}

///|
impl @provider.LanguageModelV4 for AnthropicLanguageModel with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.supported_url_rules.copy()
}

///|
impl @provider.LanguageModelV4 for AnthropicLanguageModel with fn do_generate(
  self,
  options,
) {
  self.generate_v4(options)
}

///|
impl @provider.LanguageModelV4 for AnthropicLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  self.stream_v4(options, on_event)
}
