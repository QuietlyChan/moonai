///|
/// MiniMax Chat is served through an Anthropic-compatible Messages endpoint.
pub type MiniMaxChatModel = @anthropic.AnthropicMessagesModel

///|
/// MiniMax provider factory.
pub struct MiniMaxProvider {
  priv api_key : String
  priv base_url : String
  priv video_base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
fn load_minimax_api_key(
  api_key : String,
) -> String raise @provider.LoadAPIKeyError {
  @provider_utils.load_api_key(
    api_key,
    environment_variable_name="MINIMAX_API_KEY",
    description="MiniMax",
  )
}

///|
/// Create a MiniMax provider.
pub fn create_minimax(
  api_key? : String = "",
  base_url? : String = "https://api.minimax.io/anthropic/v1",
  video_base_url? : String = "https://api.minimax.io",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> MiniMaxProvider {
  {
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    video_base_url: @provider_utils.without_trailing_slash(video_base_url),
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    id_generator: id_generator.unwrap_or(@provider_utils.generate_id),
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Camel-case provider factory matching AI SDK naming.
pub fn createMiniMax(
  api_key? : String = "",
  base_url? : String = "https://api.minimax.io/anthropic/v1",
  video_base_url? : String = "https://api.minimax.io",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> MiniMaxProvider {
  create_minimax(
    api_key~,
    base_url~,
    video_base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Select the protocol-level MiniMax Messages model.
pub fn MiniMaxProvider::chat_wire(
  self : MiniMaxProvider,
  model_id : MiniMaxChatModelId,
) -> MiniMaxChatModel raise {
  @anthropic.create_anthropic(
    api_key=self.api_key,
    base_url=self.base_url,
    provider_name="minimax.messages",
    headers=self.headers,
    anthropic_version="2023-06-01",
    supported_urls=[],
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
    api_key_environment_variable="MINIMAX_API_KEY",
    id_generator=self.id_generator,
  ).messages_wire(model_id)
}

///|
/// Select a MiniMax Messages language model.
pub fn MiniMaxProvider::chat(
  self : MiniMaxProvider,
  model_id : MiniMaxChatModelId,
) -> MiniMaxLanguageModelV4 raise {
  MiniMaxLanguageModelV4::new(self.chat_wire(model_id))
}

///|
/// Select the default MiniMax language model.
pub fn MiniMaxProvider::language_model(
  self : MiniMaxProvider,
  model_id : MiniMaxChatModelId,
) -> MiniMaxLanguageModelV4 raise {
  self.chat(model_id)
}

///|
/// Camel-case alias for `language_model`.
pub fn MiniMaxProvider::languageModel(
  self : MiniMaxProvider,
  model_id : MiniMaxChatModelId,
) -> MiniMaxLanguageModelV4 raise {
  self.language_model(model_id)
}

///|
/// Select a MiniMax native video generation model.
pub fn MiniMaxProvider::video(
  self : MiniMaxProvider,
  model_id : MiniMaxVideoModelId,
) -> MiniMaxVideoModel {
  minimax_video(
    model_id,
    api_key=self.api_key,
    base_url=self.video_base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Camel-case alias for `video`.
pub fn MiniMaxProvider::videoModel(
  self : MiniMaxProvider,
  model_id : MiniMaxVideoModelId,
) -> MiniMaxVideoModel {
  self.video(model_id)
}

///|
/// Construct the low-level MiniMax Messages wire model directly.
pub fn minimax_messages(
  model_id : MiniMaxChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.minimax.io/anthropic/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> MiniMaxChatModel raise {
  create_minimax(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).chat_wire(model_id)
}

///|
/// Construct the default V4 MiniMax language model directly.
pub fn minimax(
  model_id : MiniMaxChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.minimax.io/anthropic/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> MiniMaxLanguageModelV4 raise {
  MiniMaxLanguageModelV4::new(
    minimax_messages(
      model_id,
      api_key~,
      base_url~,
      headers~,
      idle_timeout_ms~,
      http_transport?,
      id_generator?,
    ),
  )
}
