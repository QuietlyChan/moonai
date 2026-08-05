///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn provider_name(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn language_model(
  self,
  model_id,
) {
  let model = OpenAICompatibleProvider::language_model(self, model_id)
  Some(model as &@provider.LanguageModelV4)
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn completion_model(
  self,
  model_id,
) {
  Some(OpenAICompatibleProvider::completion_model_wire(self, model_id))
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn embedding_model(
  self,
  model_id,
) {
  Some(
    OpenAICompatibleProvider::embedding_model(self, model_id)
    as &@provider.EmbeddingModelV4,
  )
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn image_model(
  self,
  model_id,
) {
  Some(
    OpenAICompatibleProvider::image_model(self, model_id)
    as &@provider.ImageModelV4,
  )
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn video_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn speech_translation_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn realtime_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn files(_self) {
  None
}

///|
pub impl @provider.Provider for OpenAICompatibleProvider with fn skills(_self) {
  None
}
