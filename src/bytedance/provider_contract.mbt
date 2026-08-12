///|
pub impl @provider.ProviderV4 for ByteDanceProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for ByteDanceProvider with fn language_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.LanguageModel,
  )
}

///|
pub impl @provider.ProviderV4 for ByteDanceProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for ByteDanceProvider with fn image_model(
  self,
  model_id,
) {
  ByteDanceProvider::image(self, model_id)
}

///|
pub impl @provider.ProviderV4 for ByteDanceProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for ByteDanceProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for ByteDanceProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for ByteDanceProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for ByteDanceProvider with fn skills(_self) {
  None
}
