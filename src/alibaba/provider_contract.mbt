///|
pub impl @provider.Provider for AlibabaProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.Provider for AlibabaProvider with fn provider_name(_self) -> String {
  "alibaba"
}

///|
pub impl @provider.Provider for AlibabaProvider with fn language_model(
  self,
  model_id,
) {
  let model = AlibabaProvider::language_model(self, model_id)
  Some(model as &@provider.LanguageModelV4)
}

///|
pub impl @provider.Provider for AlibabaProvider with fn completion_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AlibabaProvider with fn embedding_model(
  self,
  model_id,
) {
  Some(
    AlibabaProvider::embedding_model(self, model_id)
    as &@provider.EmbeddingModelV4,
  )
}

///|
pub impl @provider.Provider for AlibabaProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AlibabaProvider with fn image_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AlibabaProvider with fn video_model(
  self,
  model_id,
) {
  Some(AlibabaProvider::video(self, model_id))
}

///|
pub impl @provider.Provider for AlibabaProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AlibabaProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AlibabaProvider with fn speech_translation_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AlibabaProvider with fn realtime_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for AlibabaProvider with fn files(_self) {
  None
}

///|
pub impl @provider.Provider for AlibabaProvider with fn skills(_self) {
  None
}
