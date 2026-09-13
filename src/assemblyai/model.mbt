///|
/// AssemblyAI provider settings.
pub struct AssemblyAIProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv poll_interval_ms : Int
  priv poll_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create an AssemblyAI provider. The API key defaults to the
/// `ASSEMBLYAI_API_KEY` environment variable.
pub fn create_assemblyai(
  api_key? : String = "",
  base_url? : String = "https://api.assemblyai.com",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  poll_interval_ms? : Int = ASSEMBLYAI_POLL_INTERVAL_MS,
  poll_timeout_ms? : Int = ASSEMBLYAI_POLL_TIMEOUT_MS,
  http_transport? : &@provider_utils.HttpTransport,
) -> AssemblyAIProvider {
  {
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    poll_interval_ms,
    poll_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Camel-case provider factory matching AI SDK naming.
pub fn createAssemblyAI(
  api_key? : String = "",
  base_url? : String = "https://api.assemblyai.com",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  poll_interval_ms? : Int = ASSEMBLYAI_POLL_INTERVAL_MS,
  poll_timeout_ms? : Int = ASSEMBLYAI_POLL_TIMEOUT_MS,
  http_transport? : &@provider_utils.HttpTransport,
) -> AssemblyAIProvider {
  create_assemblyai(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    poll_interval_ms~,
    poll_timeout_ms~,
    http_transport?,
  )
}

///|
/// Select an AssemblyAI transcription model.
pub fn AssemblyAIProvider::transcription(
  self : AssemblyAIProvider,
  model_id : AssemblyAITranscriptionModelId,
) -> &@provider.TranscriptionModelV4 {
  let model = assemblyai_transcription_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    poll_interval_ms=self.poll_interval_ms,
    poll_timeout_ms=self.poll_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.TranscriptionModelV4
}

///|
/// Alias for `transcription`.
pub fn AssemblyAIProvider::transcription_model(
  self : AssemblyAIProvider,
  model_id : AssemblyAITranscriptionModelId,
) -> &@provider.TranscriptionModelV4 {
  self.transcription(model_id)
}

///|
/// Camel-case alias for `transcription_model`.
pub fn AssemblyAIProvider::transcriptionModel(
  self : AssemblyAIProvider,
  model_id : AssemblyAITranscriptionModelId,
) -> &@provider.TranscriptionModelV4 {
  self.transcription_model(model_id)
}

///|
pub impl @provider.ProviderV4 for AssemblyAIProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for AssemblyAIProvider with fn language_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.LanguageModel,
  )
}

///|
pub impl @provider.ProviderV4 for AssemblyAIProvider with fn embedding_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(
    model_id~,
    model_type=@provider.EmbeddingModel,
  )
}

///|
pub impl @provider.ProviderV4 for AssemblyAIProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for AssemblyAIProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for AssemblyAIProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for AssemblyAIProvider with fn transcription_model(
  self,
  model_id,
) {
  Some(AssemblyAIProvider::transcription_model(self, model_id))
}

///|
pub impl @provider.ProviderV4 for AssemblyAIProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for AssemblyAIProvider with fn skills(_self) {
  None
}
