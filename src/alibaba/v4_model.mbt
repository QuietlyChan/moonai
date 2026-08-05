///|
/// Alibaba's provider-owned V4 boundary. The model reuses the configured
/// OpenAI-compatible wire implementation, but the V4 identity belongs to the
/// Alibaba package rather than the generic migration adapter.
pub struct AlibabaLanguageModelV4 {
  model : AlibabaChatModel
}

///|
/// Construct a V4 Alibaba model.
pub fn AlibabaLanguageModelV4::new(
  model : AlibabaChatModel,
) -> AlibabaLanguageModelV4 {
  { model, }
}

///|
pub impl @provider.LanguageModelV4 for AlibabaLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for AlibabaLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider()
}

///|
pub impl @provider.LanguageModelV4 for AlibabaLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id()
}

///|
pub impl @provider.LanguageModelV4 for AlibabaLanguageModelV4 with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.model.supported_urls()
}

///|
pub impl @provider.LanguageModelV4 for AlibabaLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let model = @openai_compatible.OpenAICompatibleLanguageModelV4::new(
      self.model,
    )
    as &@provider.LanguageModelV4
  model.do_generate(options)
}

///|
pub impl @provider.LanguageModelV4 for AlibabaLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let model = @openai_compatible.OpenAICompatibleLanguageModelV4::new(
      self.model,
    )
    as &@provider.LanguageModelV4
  model.do_stream(options, on_event)
}
