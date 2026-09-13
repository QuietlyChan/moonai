///|
/// ElevenLabs provider settings.
pub struct ElevenLabsProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create an ElevenLabs provider. The API key defaults to the
/// `ELEVENLABS_API_KEY` environment variable.
pub fn create_elevenlabs(
  api_key? : String = "",
  base_url? : String = "https://api.elevenlabs.io",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> ElevenLabsProvider {
  {
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Camel-case provider factory matching AI SDK naming.
pub fn createElevenLabs(
  api_key? : String = "",
  base_url? : String = "https://api.elevenlabs.io",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> ElevenLabsProvider {
  create_elevenlabs(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  )
}

///|
/// Select an ElevenLabs speech (TTS) model.
pub fn ElevenLabsProvider::speech(
  self : ElevenLabsProvider,
  model_id : ElevenLabsSpeechModelId,
) -> &@provider.SpeechModelV4 {
  let model = elevenlabs_speech_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.SpeechModelV4
}

///|
/// Alias for `speech`.
pub fn ElevenLabsProvider::speech_model(
  self : ElevenLabsProvider,
  model_id : ElevenLabsSpeechModelId,
) -> &@provider.SpeechModelV4 {
  self.speech(model_id)
}

///|
/// Camel-case alias for `speech_model`.
pub fn ElevenLabsProvider::speechModel(
  self : ElevenLabsProvider,
  model_id : ElevenLabsSpeechModelId,
) -> &@provider.SpeechModelV4 {
  self.speech_model(model_id)
}

///|
/// Select an ElevenLabs transcription (STT) model.
pub fn ElevenLabsProvider::transcription(
  self : ElevenLabsProvider,
  model_id : ElevenLabsTranscriptionModelId,
) -> &@provider.TranscriptionModelV4 {
  let model = elevenlabs_transcription_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.TranscriptionModelV4
}

///|
/// Alias for `transcription`.
pub fn ElevenLabsProvider::transcription_model(
  self : ElevenLabsProvider,
  model_id : ElevenLabsTranscriptionModelId,
) -> &@provider.TranscriptionModelV4 {
  self.transcription(model_id)
}

///|
/// Camel-case alias for `transcription_model`.
pub fn ElevenLabsProvider::transcriptionModel(
  self : ElevenLabsProvider,
  model_id : ElevenLabsTranscriptionModelId,
) -> &@provider.TranscriptionModelV4 {
  self.transcription_model(model_id)
}

///|
pub impl @provider.ProviderV4 for ElevenLabsProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for ElevenLabsProvider with fn language_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.LanguageModel,
  )
}

///|
pub impl @provider.ProviderV4 for ElevenLabsProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for ElevenLabsProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for ElevenLabsProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for ElevenLabsProvider with fn speech_model(
  self,
  model_id,
) {
  Some(ElevenLabsProvider::speech_model(self, model_id))
}

///|
pub impl @provider.ProviderV4 for ElevenLabsProvider with fn transcription_model(
  self,
  model_id,
) {
  Some(ElevenLabsProvider::transcription_model(self, model_id))
}

///|
pub impl @provider.ProviderV4 for ElevenLabsProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for ElevenLabsProvider with fn skills(_self) {
  None
}
