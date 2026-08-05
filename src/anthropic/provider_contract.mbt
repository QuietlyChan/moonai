///|
pub impl @provider.Provider for AnthropicProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.Provider for AnthropicProvider with fn provider_name(self) -> String {
  self.provider_name
}

///|
pub impl @provider.Provider for AnthropicProvider with fn language_model(
  self,
  model_id,
) {
  let model = AnthropicProvider::language_model(self, model_id)
  Some(model as &@provider.LanguageModelV4)
}

///|
pub impl @provider.Provider for AnthropicProvider with fn completion_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AnthropicProvider with fn embedding_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AnthropicProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AnthropicProvider with fn image_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AnthropicProvider with fn video_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AnthropicProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AnthropicProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AnthropicProvider with fn speech_translation_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AnthropicProvider with fn realtime_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AnthropicProvider with fn files(self) {
  Some(AnthropicProvider::files(self))
}

///|
pub impl @provider.Provider for AnthropicProvider with fn skills(self) {
  Some(AnthropicProvider::skills(self))
}
