///|
pub impl @provider.ProviderV4 for OpenResponsesProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for OpenResponsesProvider with fn language_model(
  self,
  model_id,
) {
  OpenResponsesProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for OpenResponsesProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for OpenResponsesProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for OpenResponsesProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for OpenResponsesProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for OpenResponsesProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for OpenResponsesProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for OpenResponsesProvider with fn skills(_self) {
  None
}
