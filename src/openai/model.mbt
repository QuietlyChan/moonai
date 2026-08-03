///|
/// Official OpenAI provider. It composes the shared Chat Completions and Open
/// Responses protocol packages instead of duplicating their implementations.
pub struct OpenAIProvider {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv preserve_reasoning : Bool
  priv include_usage : Bool
  priv idle_timeout_ms : Int
}

///|
/// Create an official OpenAI provider factory.
pub fn create_openai(
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  provider_name? : String = "openai",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAIProvider {
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
pub fn createOpenAI(
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  provider_name? : String = "openai",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAIProvider {
  create_openai(
    api_key~,
    base_url~,
    provider_name~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
  )
}

///|
/// Compatibility name for the shared Chat Completions model type.
pub type OpenAICompatibleModel = @openai_compatible.OpenAICompatibleChatModel

///|
/// Official OpenAI Responses model type.
pub type OpenAIResponsesModel = @open_responses.OpenResponsesLanguageModel

///|
/// Select an official OpenAI Chat Completions model.
pub fn OpenAIProvider::chat(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAICompatibleModel {
  @openai_compatible.create_openai_compatible(
    provider_name=self.provider_name,
    base_url=self.base_url,
    api_key=self.api_key,
    headers=self.headers,
    preserve_reasoning=self.preserve_reasoning,
    include_usage=self.include_usage,
    idle_timeout_ms=self.idle_timeout_ms,
  ).chat_model(model_id)
}

///|
/// Select an official OpenAI Responses API model.
pub fn OpenAIProvider::responses(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesModel {
  @open_responses.create_open_responses(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/responses"),
    api_key=self.api_key,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
  ).responses(model_id)
}

///|
/// Select the default language model. AI SDK 7 uses the Responses API for
/// official OpenAI models.
pub fn OpenAIProvider::language_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesModel {
  self.responses(model_id)
}

///|
/// Construct the default official OpenAI model using the Responses API.
pub fn openai(
  model_id : String,
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
) -> OpenAIResponsesModel {
  create_openai(api_key~, base_url~, headers~, idle_timeout_ms~).responses(
    model_id,
  )
}

///|
/// Construct an official OpenAI Chat Completions model explicitly.
pub fn openai_chat(
  model_id : String,
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompatibleModel {
  create_openai(
    api_key~,
    base_url~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
  ).chat(model_id)
}

///|
/// Backward-compatible shortcut for the standalone openai_compatible package.
pub fn openai_compatible(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompatibleModel {
  @openai_compatible.openai_compatible(
    provider_name~,
    base_url~,
    model_id~,
    api_key~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
  )
}
