///|
pub impl @provider.ProviderV4 for OpenAICompatibleProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for OpenAICompatibleProvider with fn language_model(
  self,
  model_id,
) {
  OpenAICompatibleProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for OpenAICompatibleProvider with fn embedding_model(
  self,
  model_id,
) {
  OpenAICompatibleProvider::embedding_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for OpenAICompatibleProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for OpenAICompatibleProvider with fn image_model(
  self,
  model_id,
) {
  OpenAICompatibleProvider::image_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for OpenAICompatibleProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for OpenAICompatibleProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for OpenAICompatibleProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for OpenAICompatibleProvider with fn skills(_self) {
  None
}
