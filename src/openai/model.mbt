///|
/// Official OpenAI provider. Each model family owns its provider-specific
/// protocol implementation and shares only provider-neutral utilities.
pub struct OpenAIProvider {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv preserve_reasoning : Bool
  priv include_usage : Bool
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv websocket_connector : &@provider_utils.WebSocketConnector
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// The default endpoint used when neither the constructor nor the environment
/// provides an OpenAI base URL.
const OPENAI_DEFAULT_BASE_URL : String = "https://api.openai.com/v1"

///|
/// Resolve the explicit base URL, `OPENAI_BASE_URL`, and the official default
/// in that order. Keeping this at the provider factory boundary makes every
/// model family, Files, and Skills client observe the same endpoint.
fn resolve_openai_base_url(base_url : String) -> String {
  @provider_utils.without_trailing_slash(
    @provider_utils.load_optional_setting(
      base_url,
      environment_variable_name="OPENAI_BASE_URL",
    ).unwrap_or(OPENAI_DEFAULT_BASE_URL),
  )
}

///|
/// Resolve the official OpenAI credential using the same explicit-setting
/// then environment-variable precedence as AI SDK.
fn load_openai_api_key(
  api_key : String,
) -> String raise @provider.LoadAPIKeyError {
  @provider_utils.load_api_key(
    api_key,
    environment_variable_name="OPENAI_API_KEY",
    description="OpenAI",
  )
}

///|
/// Create an official OpenAI provider factory.
pub fn create_openai(
  api_key? : String = "",
  base_url? : String = "",
  provider_name? : String = "openai",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  websocket_connector? : &@provider_utils.WebSocketConnector,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> OpenAIProvider {
  let openai_headers : Map[String, String] = Map([])
  if organization != "" {
    openai_headers["OpenAI-Organization"] = organization
  }
  if project != "" {
    openai_headers["OpenAI-Project"] = project
  }
  {
    provider_name,
    api_key,
    base_url: resolve_openai_base_url(base_url),
    headers: @provider_utils.merge_headers(openai_headers, headers),
    preserve_reasoning,
    include_usage,
    idle_timeout_ms,
    id_generator: id_generator.unwrap_or(@provider_utils.generate_id),
    websocket_connector: websocket_connector.unwrap_or(
      @provider_utils.native_websocket_connector(),
    ),
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// AI SDK-style camel-case provider factory.
pub fn createOpenAI(
  api_key? : String = "",
  base_url? : String = "",
  provider_name? : String = "openai",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  websocket_connector? : &@provider_utils.WebSocketConnector,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> OpenAIProvider {
  create_openai(
    api_key~,
    base_url~,
    provider_name~,
    organization~,
    project~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
    websocket_connector?,
    http_transport?,
    id_generator?,
  )
}

///|

///|
/// Select the protocol-level official Chat Completions model.
pub fn OpenAIProvider::chat_wire(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIChatModel {
  {
    provider_name: "\{self.provider_name}.chat",
    base_url: self.base_url,
    api_key: self.api_key,
    model_id,
    headers: @provider_utils.copy_headers(self.headers),
    preserve_reasoning: self.preserve_reasoning,
    include_usage: self.include_usage,
    idle_timeout_ms: self.idle_timeout_ms,
    id_generator: self.id_generator,
    http_transport: self.http_transport,
  }
}

///|
/// Select an official OpenAI Chat Completions language model.
pub fn OpenAIProvider::chat(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIChatLanguageModelV4 {
  OpenAIChatLanguageModelV4::new(self.chat_wire(model_id))
}

///|
/// Snake-case alias for selecting the Chat Completions model.
pub fn OpenAIProvider::chat_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIChatLanguageModelV4 {
  self.chat(model_id)
}

///|
/// Camel-case alias for selecting the Chat Completions model.
pub fn OpenAIProvider::chatModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIChatLanguageModelV4 {
  self.chat(model_id)
}

///|
/// Select an official OpenAI text embedding model.
pub fn OpenAIProvider::embedding(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  openai_embedding_model(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Convenience alias for embedding model selection.
pub fn OpenAIProvider::embedding_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  self.embedding(model_id)
}

///|
/// AI SDK-style camel-case spelling for `embedding`.
pub fn OpenAIProvider::embeddingModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  self.embedding(model_id)
}

///|
/// Explicit AI SDK terminology for text embeddings.
pub fn OpenAIProvider::text_embedding(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  self.embedding(model_id)
}

///|
/// AI SDK-style camel-case spelling for `text_embedding`.
pub fn OpenAIProvider::textEmbedding(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  self.embedding(model_id)
}

///|
/// Explicit AI SDK terminology for text embedding model selection.
pub fn OpenAIProvider::text_embedding_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  self.embedding(model_id)
}

///|
/// AI SDK-style camel-case spelling for `text_embedding_model`.
pub fn OpenAIProvider::textEmbeddingModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  self.embedding(model_id)
}

///|
/// Select the protocol-level official `/completions` model.
pub fn OpenAIProvider::completion_wire(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAICompletionModel {
  openai_completion_model(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    include_usage=self.include_usage,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Select an official `/completions` language model.
pub fn OpenAIProvider::completion(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAICompletionLanguageModelV4 {
  OpenAICompletionLanguageModelV4::new(self.completion_wire(model_id))
}

///|
/// Convenience alias for completion model selection.
pub fn OpenAIProvider::completion_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAICompletionLanguageModelV4 {
  self.completion(model_id)
}

///|
/// AI SDK-style camel-case spelling for `completion`.
pub fn OpenAIProvider::completionModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAICompletionLanguageModelV4 {
  self.completion(model_id)
}

///|
fn openai_image_max_images_per_call(model_id : String) -> Int {
  match model_id {
    "dall-e-3" => 1
    "dall-e-2" => 10
    value if value.has_prefix("gpt-image-") => 10
    "chatgpt-image-latest" => 10
    _ => 1
  }
}

///|
fn openai_image_requires_response_format(model_id : String) -> Bool {
  !model_id.has_prefix("gpt-image-") && !model_id.has_prefix("chatgpt-image-")
}

///|
/// Select an official OpenAI image generation model.
pub fn OpenAIProvider::image(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIImageModel {
  openai_image_model(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    max_images_per_call=openai_image_max_images_per_call(model_id),
    include_response_format=openai_image_requires_response_format(model_id),
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Convenience alias for image model selection.
pub fn OpenAIProvider::image_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIImageModel {
  self.image(model_id)
}

///|
/// AI SDK-style camel-case spelling for `image`.
pub fn OpenAIProvider::imageModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIImageModel {
  self.image(model_id)
}

///|
/// Select the official OpenAI Files API.
pub fn OpenAIProvider::files(self : OpenAIProvider) -> OpenAIFiles {
  openai_files(
    provider_name=self.provider_name,
    base_url=self.base_url,
    api_key=self.api_key,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Select the official OpenAI Skills API.
pub fn OpenAIProvider::skills(self : OpenAIProvider) -> OpenAISkills {
  openai_skills(
    provider_name=self.provider_name,
    base_url=self.base_url,
    api_key=self.api_key,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Select an official OpenAI text-to-speech model.
pub fn OpenAIProvider::speech(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAISpeechModel {
  openai_speech_model(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Convenience alias for speech model selection.
pub fn OpenAIProvider::speech_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAISpeechModel {
  self.speech(model_id)
}

///|
/// Camel-case alias for speech model selection.
pub fn OpenAIProvider::speechModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAISpeechModel {
  self.speech(model_id)
}

///|
/// Select an official OpenAI transcription model.
pub fn OpenAIProvider::transcription(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAITranscriptionModel {
  openai_transcription_model(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
    websocket_connector=self.websocket_connector,
  )
}

///|
/// Convenience alias for transcription model selection.
pub fn OpenAIProvider::transcription_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAITranscriptionModel {
  self.transcription(model_id)
}

///|
/// Camel-case alias for transcription model selection.
pub fn OpenAIProvider::transcriptionModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAITranscriptionModel {
  self.transcription(model_id)
}

///|
/// Select an OpenAI Realtime streaming speech translation model.
pub fn OpenAIProvider::translation(
  self : OpenAIProvider,
  model_id : OpenAITranslationModelId,
) -> OpenAITranslationModel {
  openai_translation_model(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    websocket_connector=self.websocket_connector,
  )
}

///|
/// AI SDK-compatible explicit speech translation model factory.
pub fn OpenAIProvider::speech_translation_model(
  self : OpenAIProvider,
  model_id : OpenAITranslationModelId,
) -> OpenAITranslationModel {
  self.translation(model_id)
}

///|
/// Camel-case alias for `speech_translation_model`.
pub fn OpenAIProvider::speechTranslationModel(
  self : OpenAIProvider,
  model_id : OpenAITranslationModelId,
) -> OpenAITranslationModel {
  self.translation(model_id)
}

///|
/// Return the OpenAI Realtime model factory. A factory object is used because
/// MoonBit does not have TypeScript-style callable objects with methods.
pub fn OpenAIProvider::experimental_realtime(
  self : OpenAIProvider,
) -> OpenAIRealtimeFactory {
  openai_realtime_factory(
    provider_name=self.provider_name,
    base_url=self.base_url,
    api_key=self.api_key,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Camel-case alias for the experimental realtime factory.
pub fn OpenAIProvider::experimentalRealtime(
  self : OpenAIProvider,
) -> OpenAIRealtimeFactory {
  self.experimental_realtime()
}

///|
/// Select an OpenAI Realtime model directly.
pub fn OpenAIProvider::realtime(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIRealtimeModel {
  self.experimental_realtime().model(model_id)
}

///|
/// Explicit realtime model alias.
pub fn OpenAIProvider::realtime_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIRealtimeModel {
  self.realtime(model_id)
}

///|
/// Camel-case alias for `realtime_model`.
pub fn OpenAIProvider::realtimeModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIRealtimeModel {
  self.realtime(model_id)
}

///|
/// Select the protocol-level official Responses API model.
pub fn OpenAIProvider::responses_wire(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesModel {
  {
    provider_name: "\{self.provider_name}.responses",
    url: @provider_utils.append_path(self.base_url, "/responses"),
    api_key: self.api_key,
    model_id,
    headers: @provider_utils.copy_headers(self.headers),
    idle_timeout_ms: self.idle_timeout_ms,
    id_generator: self.id_generator,
    http_transport: self.http_transport,
  }
}

///|
/// Select an official OpenAI Responses API language model.
pub fn OpenAIProvider::responses(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesLanguageModelV4 {
  OpenAIResponsesLanguageModelV4::new(self.responses_wire(model_id))
}

///|
/// Explicit alias for selecting an OpenAI Responses model.
pub fn OpenAIProvider::responses_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesLanguageModelV4 {
  self.responses(model_id)
}

///|
/// Camel-case alias for selecting an OpenAI Responses model.
pub fn OpenAIProvider::responsesModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesLanguageModelV4 {
  self.responses(model_id)
}

///|
/// Select the default language model. AI SDK 7 uses the Responses API for
/// official OpenAI models.
pub fn OpenAIProvider::language_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesLanguageModelV4 {
  self.responses(model_id)
}

///|
/// AI SDK-style camel-case spelling for `language_model`.
pub fn OpenAIProvider::languageModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesLanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Construct the default official OpenAI model using the Responses API.
pub fn openai(
  model_id : String,
  api_key? : String = "",
  base_url? : String = "",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> OpenAIResponsesLanguageModelV4 {
  create_openai(
    api_key~,
    base_url~,
    organization~,
    project~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}

///|
/// Construct an official OpenAI Chat Completions language model explicitly.
pub fn openai_chat(
  model_id : String,
  api_key? : String = "",
  base_url? : String = "",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> OpenAIChatLanguageModelV4 {
  create_openai(
    api_key~,
    base_url~,
    organization~,
    project~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).chat(model_id)
}

///|
/// Construct the protocol-level Chat Completions model directly.
pub fn openai_chat_wire(
  model_id : String,
  api_key? : String = "",
  base_url? : String = "",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> OpenAIChatModel {
  create_openai(
    api_key~,
    base_url~,
    organization~,
    project~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).chat_wire(model_id)
}

///|
/// Construct an official OpenAI text embedding model.
pub fn openai_embedding(
  model_id : String,
  api_key? : String = "",
  base_url? : String = "",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> OpenAIEmbeddingModel {
  create_openai(
    api_key~,
    base_url~,
    organization~,
    project~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  ).embedding(model_id)
}

///|
/// Construct an official OpenAI `/completions` language model.
pub fn openai_completion(
  model_id : String,
  api_key? : String = "",
  base_url? : String = "",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> OpenAICompletionLanguageModelV4 {
  create_openai(
    api_key~,
    base_url~,
    organization~,
    project~,
    headers~,
    include_usage~,
    idle_timeout_ms~,
    http_transport?,
  ).completion(model_id)
}

///|
/// Construct the protocol-level official `/completions` model directly.
pub fn openai_completion_wire(
  model_id : String,
  api_key? : String = "",
  base_url? : String = "",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> OpenAICompletionModel {
  create_openai(
    api_key~,
    base_url~,
    organization~,
    project~,
    headers~,
    include_usage~,
    idle_timeout_ms~,
    http_transport?,
  ).completion_wire(model_id)
}

///|
/// Construct an official OpenAI image generation model.
pub fn openai_image(
  model_id : String,
  api_key? : String = "",
  base_url? : String = "",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> OpenAIImageModel {
  create_openai(
    api_key~,
    base_url~,
    organization~,
    project~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  ).image(model_id)
}

///|
/// Construct an official OpenAI text-to-speech model.
pub fn openai_speech(
  model_id : String,
  api_key? : String = "",
  base_url? : String = "",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> OpenAISpeechModel {
  create_openai(
    api_key~,
    base_url~,
    organization~,
    project~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  ).speech(model_id)
}

///|
/// Construct an official OpenAI transcription model.
pub fn openai_transcription(
  model_id : String,
  api_key? : String = "",
  base_url? : String = "",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  websocket_connector? : &@provider_utils.WebSocketConnector,
  http_transport? : &@provider_utils.HttpTransport,
) -> OpenAITranscriptionModel {
  create_openai(
    api_key~,
    base_url~,
    organization~,
    project~,
    headers~,
    idle_timeout_ms~,
    websocket_connector?,
    http_transport?,
  ).transcription(model_id)
}

///|
/// Construct an official OpenAI Realtime speech translation model.
pub fn openai_translation(
  model_id : OpenAITranslationModelId,
  api_key? : String = "",
  base_url? : String = "",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  websocket_connector? : &@provider_utils.WebSocketConnector,
) -> OpenAITranslationModel {
  create_openai(
    api_key~,
    base_url~,
    organization~,
    project~,
    headers~,
    websocket_connector?,
  ).translation(model_id)
}

///|
/// Construct an official OpenAI Realtime model.
pub fn openai_realtime(
  model_id : String,
  api_key? : String = "",
  base_url? : String = "",
  organization? : String = "",
  project? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> OpenAIRealtimeModel {
  create_openai(
    api_key~,
    base_url~,
    organization~,
    project~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  ).realtime(model_id)
}
