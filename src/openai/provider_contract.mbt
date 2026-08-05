///|
pub impl @provider.Provider for OpenAIProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.Provider for OpenAIProvider with fn provider_name(self) -> String {
  self.provider_name
}

///|
pub impl @provider.Provider for OpenAIProvider with fn language_model(
  self,
  model_id,
) {
  let model = OpenAIProvider::language_model(self, model_id)
  Some(model as &@provider.LanguageModelV4)
}

///|
pub impl @provider.Provider for OpenAIProvider with fn completion_model(
  self,
  model_id,
) {
  Some(OpenAIProvider::completion_wire(self, model_id))
}

///|
pub impl @provider.Provider for OpenAIProvider with fn embedding_model(
  self,
  model_id,
) {
  Some(OpenAIProvider::embedding(self, model_id) as &@provider.EmbeddingModelV4)
}

///|
pub impl @provider.Provider for OpenAIProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for OpenAIProvider with fn image_model(
  self,
  model_id,
) {
  Some(OpenAIProvider::image(self, model_id) as &@provider.ImageModelV4)
}

///|
pub impl @provider.Provider for OpenAIProvider with fn video_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for OpenAIProvider with fn speech_model(
  self,
  model_id,
) {
  Some(OpenAIProvider::speech(self, model_id))
}

///|
pub impl @provider.Provider for OpenAIProvider with fn transcription_model(
  self,
  model_id,
) {
  Some(OpenAIProvider::transcription(self, model_id))
}

///|
pub impl @provider.Provider for OpenAIProvider with fn speech_translation_model(
  self,
  model_id,
) {
  Some(OpenAIProvider::translation(self, model_id))
}

///|
pub impl @provider.Provider for OpenAIProvider with fn realtime_model(
  self,
  model_id,
) {
  Some(OpenAIProvider::realtime(self, model_id))
}

///|
pub impl @provider.Provider for OpenAIProvider with fn files(self) {
  Some(OpenAIProvider::files(self))
}

///|
pub impl @provider.Provider for OpenAIProvider with fn skills(self) {
  Some(OpenAIProvider::skills(self))
}
