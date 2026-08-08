///|
pub impl @provider.ProviderV4 for MiniMaxProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for MiniMaxProvider with fn language_model(
  self,
  model_id,
) {
  MiniMaxProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for MiniMaxProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for MiniMaxProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for MiniMaxProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for MiniMaxProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for MiniMaxProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for MiniMaxProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for MiniMaxProvider with fn skills(_self) {
  None
}
