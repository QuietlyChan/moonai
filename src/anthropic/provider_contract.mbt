///|
pub impl @provider.ProviderV4 for AnthropicProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for AnthropicProvider with fn language_model(
  self,
  model_id,
) {
  AnthropicProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for AnthropicProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for AnthropicProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for AnthropicProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for AnthropicProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for AnthropicProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for AnthropicProvider with fn files(self) {
  Some(AnthropicProvider::files(self))
}

///|
pub impl @provider.ProviderV4 for AnthropicProvider with fn skills(self) {
  Some(AnthropicProvider::skills(self))
}
