///|
pub impl @provider.Provider for DeepSeekProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn provider_name(self) -> String {
  self.provider_name
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn language_model(
  self,
  model_id,
) {
  let model = DeepSeekProvider::language_model(self, model_id)
  Some(model as &@provider.LanguageModelV4)
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn completion_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn embedding_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn image_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn video_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn speech_translation_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn realtime_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn files(_self) {
  None
}

///|
pub impl @provider.Provider for DeepSeekProvider with fn skills(_self) {
  None
}
