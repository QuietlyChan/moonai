///|
pub impl @provider.ProviderV4 for OpenAIProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for OpenAIProvider with fn language_model(
  self,
  model_id,
) {
  OpenAIProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for OpenAIProvider with fn embedding_model(
  self,
  model_id,
) {
  OpenAIProvider::embedding(self, model_id)
}

///|
pub impl @provider.ProviderV4 for OpenAIProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for OpenAIProvider with fn image_model(
  self,
  model_id,
) {
  OpenAIProvider::image(self, model_id)
}

///|
pub impl @provider.ProviderV4 for OpenAIProvider with fn speech_model(
  self,
  model_id,
) {
  Some(OpenAIProvider::speech(self, model_id))
}

///|
pub impl @provider.ProviderV4 for OpenAIProvider with fn transcription_model(
  self,
  model_id,
) {
  Some(OpenAIProvider::transcription(self, model_id))
}

///|
pub impl @provider.ProviderV4 for OpenAIProvider with fn files(self) {
  Some(OpenAIProvider::files(self))
}

///|
pub impl @provider.ProviderV4 for OpenAIProvider with fn skills(self) {
  Some(OpenAIProvider::skills(self))
}
