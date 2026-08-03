///|
/// Configuration shared by models served by one OpenAI-compatible endpoint.
pub struct OpenAICompatibleProvider {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv preserve_reasoning : Bool
  priv include_usage : Bool
  priv idle_timeout_ms : Int
}

///|
/// Create an OpenAI-compatible provider factory.
pub fn create_openai_compatible(
  provider_name~ : String,
  base_url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompatibleProvider {
  {
    provider_name,
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    preserve_reasoning,
    include_usage,
    idle_timeout_ms,
  }
}

///|
/// AI SDK-style camel-case provider factory.
pub fn createOpenAICompatible(
  provider_name~ : String,
  base_url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompatibleProvider {
  create_openai_compatible(
    provider_name~,
    base_url~,
    api_key~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
  )
}

///|
/// Select a Chat Completions model.
pub fn OpenAICompatibleProvider::chat_model(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleChatModel {
  {
    provider_name: "\{self.provider_name}.chat",
    api_key: self.api_key,
    base_url: self.base_url,
    model_id,
    headers: @provider_utils.copy_headers(self.headers),
    preserve_reasoning: self.preserve_reasoning,
    include_usage: self.include_usage,
    idle_timeout_ms: self.idle_timeout_ms,
  }
}

///|
/// Select the default language model, which is a chat model for this package.
pub fn OpenAICompatibleProvider::language_model(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleChatModel {
  self.chat_model(model_id)
}

///|
/// Short alias for `chat_model`.
pub fn OpenAICompatibleProvider::chat(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleChatModel {
  self.chat_model(model_id)
}

///|
/// A chat model using the OpenAI Chat Completions wire protocol.
pub struct OpenAICompatibleChatModel {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv model_id : String
  priv headers : Map[String, String]
  priv preserve_reasoning : Bool
  priv include_usage : Bool
  priv idle_timeout_ms : Int
}

///|
/// Compatibility type name used by the first moonai release.
pub type OpenAICompatibleModel = OpenAICompatibleChatModel

///|
/// Construct an OpenAI-compatible chat model directly.
pub fn openai_compatible(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompatibleChatModel {
  create_openai_compatible(
    provider_name~,
    base_url~,
    api_key~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
  ).chat_model(model_id)
}

///|
fn OpenAICompatibleChatModel::chat_completions_url(
  self : OpenAICompatibleChatModel,
) -> String {
  @provider_utils.append_path(self.base_url, "/chat/completions")
}

///|
fn OpenAICompatibleChatModel::request_headers(
  self : OpenAICompatibleChatModel,
) -> Map[String, String] {
  let headers = @provider_utils.copy_headers(self.headers)
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  if self.api_key != "" {
    headers["Authorization"] = "Bearer \{self.api_key}"
  }
  headers
}

///|
pub impl @moonai.ChatModel for OpenAICompatibleChatModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @moonai.ChatModel for OpenAICompatibleChatModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @moonai.ChatModel for OpenAICompatibleChatModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_chat(options, on_event)
}
