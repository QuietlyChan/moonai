///|
type ApiKey = String

///|
/// Configuration shared by models created from one Anthropic endpoint.
pub struct AnthropicProvider {
  priv provider_name : String
  priv api_key : ApiKey
  priv auth_token : String
  priv base_url : String
  priv headers : Map[String, String]
  priv anthropic_version : String
  priv beta_features : Array[String]
  priv idle_timeout_ms : Int
}

///|
fn copy_strings(values : Array[String]) -> Array[String] {
  [
    for value in values => value
  ]
}

///|
fn append_unique(values : Array[String], value : String) -> Unit {
  for existing in values {
    if existing == value {
      return
    }
  }
  values.push(value)
}

///|
fn normalize_base_url(base_url : String) -> String {
  let base = @provider_utils.without_trailing_slash(base_url)
  if base == "https://api.anthropic.com" {
    "https://api.anthropic.com/v1"
  } else {
    base
  }
}

///|
/// Create a reusable Anthropic provider factory.
pub fn create_anthropic(
  api_key? : String = "",
  auth_token? : String = "",
  base_url? : String = "https://api.anthropic.com/v1",
  provider_name? : String = "anthropic.messages",
  headers? : Map[String, String] = Map([]),
  anthropic_version? : String = "2023-06-01",
  beta_features? : Array[String] = [],
  idle_timeout_ms? : Int = 120_000,
) -> AnthropicProvider raise {
  guard api_key == "" || auth_token == "" else {
    fail("Anthropic accepts either api_key or auth_token, not both")
  }
  guard api_key != "" || auth_token != "" else {
    fail("Anthropic requires api_key or auth_token")
  }
  {
    provider_name,
    api_key,
    auth_token,
    base_url: normalize_base_url(base_url),
    headers: @provider_utils.copy_headers(headers),
    anthropic_version,
    beta_features: copy_strings(beta_features),
    idle_timeout_ms,
  }
}

///|
/// Camel-case compatibility alias for AI SDK users.
pub fn createAnthropic(
  api_key? : String = "",
  auth_token? : String = "",
  base_url? : String = "https://api.anthropic.com/v1",
  provider_name? : String = "anthropic.messages",
  headers? : Map[String, String] = Map([]),
  anthropic_version? : String = "2023-06-01",
  beta_features? : Array[String] = [],
  idle_timeout_ms? : Int = 120_000,
) -> AnthropicProvider raise {
  create_anthropic(
    api_key~,
    auth_token~,
    base_url~,
    provider_name~,
    headers~,
    anthropic_version~,
    beta_features~,
    idle_timeout_ms~,
  )
}

///|
/// Select a Messages API model from this provider.
pub fn AnthropicProvider::chat(
  self : AnthropicProvider,
  model_id : String,
) -> AnthropicMessagesModel {
  {
    provider_name: self.provider_name,
    api_key: self.api_key,
    auth_token: self.auth_token,
    base_url: self.base_url,
    model_id,
    headers: @provider_utils.copy_headers(self.headers),
    anthropic_version: self.anthropic_version,
    beta_features: copy_strings(self.beta_features),
    idle_timeout_ms: self.idle_timeout_ms,
  }
}

///|
/// Select a model using the AI SDK `messages` naming.
pub fn AnthropicProvider::messages(
  self : AnthropicProvider,
  model_id : String,
) -> AnthropicMessagesModel {
  self.chat(model_id)
}

///|
/// Select a model using an explicit language-model name.
pub fn AnthropicProvider::language_model(
  self : AnthropicProvider,
  model_id : String,
) -> AnthropicMessagesModel {
  self.chat(model_id)
}

///|
/// One language model served through the Anthropic Messages API.
pub struct AnthropicMessagesModel {
  priv provider_name : String
  priv api_key : ApiKey
  priv auth_token : String
  priv base_url : String
  priv model_id : String
  priv headers : Map[String, String]
  priv anthropic_version : String
  priv beta_features : Array[String]
  priv idle_timeout_ms : Int
}

///|
/// Construct an official Anthropic model directly.
pub fn anthropic(
  model_id : String,
  api_key? : String = "",
  auth_token? : String = "",
  base_url? : String = "https://api.anthropic.com/v1",
  headers? : Map[String, String] = Map([]),
  anthropic_version? : String = "2023-06-01",
  beta_features? : Array[String] = [],
  idle_timeout_ms? : Int = 120_000,
) -> AnthropicMessagesModel raise {
  create_anthropic(
    api_key~,
    auth_token~,
    base_url~,
    headers~,
    anthropic_version~,
    beta_features~,
    idle_timeout_ms~,
  ).chat(model_id)
}

///|
fn AnthropicMessagesModel::messages_url(
  self : AnthropicMessagesModel,
) -> String {
  @provider_utils.append_path(self.base_url, "/messages")
}

///|
fn AnthropicMessagesModel::request_beta_features(
  self : AnthropicMessagesModel,
  options : @moonai.ChatCallOptions,
) -> Array[String] {
  let features = copy_strings(self.beta_features)
  let mut structured = options.response_format is @moonai.JsonSchema(..)
  if !structured {
    for tool in options.tools {
      if tool.strict {
        structured = true
        break
      }
    }
  }
  if structured {
    append_unique(features, "structured-outputs-2025-11-13")
  }
  features
}

///|
fn AnthropicMessagesModel::request_headers(
  self : AnthropicMessagesModel,
  options : @moonai.ChatCallOptions,
) -> Map[String, String] {
  let headers = @provider_utils.copy_headers(self.headers)
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["anthropic-version"] = self.anthropic_version
  if self.api_key != "" {
    headers["x-api-key"] = self.api_key
  }
  if self.auth_token != "" {
    headers["Authorization"] = "Bearer \{self.auth_token}"
  }
  let beta_features = self.request_beta_features(options)
  if beta_features.length() > 0 {
    headers["anthropic-beta"] = beta_features.join(",")
  }
  headers
}

///|
pub impl @moonai.ChatModel for AnthropicMessagesModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @moonai.ChatModel for AnthropicMessagesModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @moonai.ChatModel for AnthropicMessagesModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_messages(options, on_event)
}
