///|
/// Cartesia provider settings.
pub struct CartesiaProvider {
  priv api_key : String
  priv base_url : String
  priv api_version : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a Cartesia provider. The API key defaults to the
/// `CARTESIA_API_KEY` environment variable.
pub fn create_cartesia(
  api_key? : String = "",
  base_url? : String = "https://api.cartesia.ai",
  api_version? : String = CARTESIA_API_VERSION,
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> CartesiaProvider {
  {
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    api_version,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Camel-case provider factory matching AI SDK naming.
pub fn createCartesia(
  api_key? : String = "",
  base_url? : String = "https://api.cartesia.ai",
  api_version? : String = CARTESIA_API_VERSION,
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> CartesiaProvider {
  create_cartesia(
    api_key~,
    base_url~,
    api_version~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  )
}

///|
/// Select a Cartesia speech (TTS) model.
pub fn CartesiaProvider::speech(
  self : CartesiaProvider,
  model_id : CartesiaSpeechModelId,
) -> &@provider.SpeechModelV4 {
  let model = cartesia_speech_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    api_version=self.api_version,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.SpeechModelV4
}

///|
/// Alias for `speech`.
pub fn CartesiaProvider::speech_model(
  self : CartesiaProvider,
  model_id : CartesiaSpeechModelId,
) -> &@provider.SpeechModelV4 {
  self.speech(model_id)
}

///|
/// Camel-case alias for `speech_model`.
pub fn CartesiaProvider::speechModel(
  self : CartesiaProvider,
  model_id : CartesiaSpeechModelId,
) -> &@provider.SpeechModelV4 {
  self.speech_model(model_id)
}

///|
/// Select a Cartesia transcription (STT) model.
pub fn CartesiaProvider::transcription(
  self : CartesiaProvider,
  model_id : CartesiaTranscriptionModelId,
) -> &@provider.TranscriptionModelV4 {
  let model = cartesia_transcription_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    api_version=self.api_version,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.TranscriptionModelV4
}

///|
/// Alias for `transcription`.
pub fn CartesiaProvider::transcription_model(
  self : CartesiaProvider,
  model_id : CartesiaTranscriptionModelId,
) -> &@provider.TranscriptionModelV4 {
  self.transcription(model_id)
}

///|
/// Camel-case alias for `transcription_model`.
pub fn CartesiaProvider::transcriptionModel(
  self : CartesiaProvider,
  model_id : CartesiaTranscriptionModelId,
) -> &@provider.TranscriptionModelV4 {
  self.transcription_model(model_id)
}

///|
pub impl @provider.ProviderV4 for CartesiaProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for CartesiaProvider with fn language_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.LanguageModel,
  )
}

///|
pub impl @provider.ProviderV4 for CartesiaProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for CartesiaProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for CartesiaProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for CartesiaProvider with fn speech_model(
  self,
  model_id,
) {
  Some(CartesiaProvider::speech_model(self, model_id))
}

///|
pub impl @provider.ProviderV4 for CartesiaProvider with fn transcription_model(
  self,
  model_id,
) {
  Some(CartesiaProvider::transcription_model(self, model_id))
}

///|
pub impl @provider.ProviderV4 for CartesiaProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for CartesiaProvider with fn skills(_self) {
  None
}
