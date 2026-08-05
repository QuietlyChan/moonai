///|
pub impl @provider.Provider for MiniMaxProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn provider_name(_self) -> String {
  "minimax"
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn language_model(
  self,
  model_id,
) {
  let model = MiniMaxProvider::language_model(self, model_id)
  Some(model as &@provider.LanguageModelV4)
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn completion_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn embedding_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn image_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn video_model(
  self,
  model_id,
) {
  Some(MiniMaxProvider::video(self, model_id))
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn speech_translation_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn realtime_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn files(_self) {
  None
}

///|
pub impl @provider.Provider for MiniMaxProvider with fn skills(_self) {
  None
}
