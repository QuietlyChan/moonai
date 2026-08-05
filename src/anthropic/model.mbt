///|
type ApiKey = String

///|
/// The default versioned endpoint used by Anthropic Messages, Files, and
/// Skills when no explicit or environment setting is supplied.
const ANTHROPIC_DEFAULT_BASE_URL : String = "https://api.anthropic.com/v1"

///|
/// Configuration shared by models created from one Anthropic endpoint.
pub struct AnthropicProvider {
  priv provider_name : String
  priv api_key : ApiKey
  priv auth_token : String
  priv api_key_environment_variable : String?
  priv base_url : String
  priv headers : Map[String, String]
  priv anthropic_version : String
  priv beta_features : Array[String]
  priv supported_url_rules : Array[@provider.SupportedUrlRule]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
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
/// Resolve the explicit base URL, `ANTHROPIC_BASE_URL`, and the official
/// default in that order. The normalization also turns the bare official URL
/// into the versioned `/v1` endpoint used by all Anthropic APIs.
fn resolve_anthropic_base_url(base_url : String) -> String {
  normalize_base_url(
    @provider_utils.load_optional_setting(
      base_url,
      environment_variable_name="ANTHROPIC_BASE_URL",
    ).unwrap_or(ANTHROPIC_DEFAULT_BASE_URL),
  )
}

///|
fn anthropic_authentication_headers(
  api_key : String,
  auth_token : String,
  api_key_environment_variable : String?,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  if auth_token != "" {
    { "Authorization": "Bearer \{auth_token}" }
  } else {
    {
      "x-api-key": @provider_utils.load_api_key(
        api_key,
        environment_variable_name=api_key_environment_variable.unwrap_or(
          "ANTHROPIC_API_KEY",
        ),
        description="Anthropic",
      ),
    }
  }
}

///|
/// Create a reusable Anthropic provider factory.
pub fn create_anthropic(
  api_key? : String = "",
  auth_token? : String = "",
  base_url? : String = "",
  provider_name? : String = "anthropic.messages",
  headers? : Map[String, String] = Map([]),
  anthropic_version? : String = "2023-06-01",
  beta_features? : Array[String] = [],
  supported_urls? : Array[@provider.SupportedUrlRule] = [
    @provider.SupportedUrlRule::http("image/*"),
    @provider.SupportedUrlRule::http("application/pdf"),
  ],
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
) -> AnthropicProvider raise {
  guard api_key == "" || auth_token == "" else {
    raise @provider.InvalidArgumentError(
      argument="api_key/auth_token",
      message="Both api_key and auth_token were provided. Please use only one authentication method.",
    )
  }
  {
    provider_name,
    api_key,
    auth_token,
    api_key_environment_variable,
    base_url: resolve_anthropic_base_url(base_url),
    headers: @provider_utils.copy_headers(headers),
    anthropic_version,
    beta_features: copy_strings(beta_features),
    supported_url_rules: supported_urls.copy(),
    idle_timeout_ms,
    id_generator: id_generator.unwrap_or(@provider_utils.generate_id),
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// AI SDK-style camel-case spelling for `create_anthropic`.
pub fn createAnthropic(
  api_key? : String = "",
  auth_token? : String = "",
  base_url? : String = "",
  provider_name? : String = "anthropic.messages",
  headers? : Map[String, String] = Map([]),
  anthropic_version? : String = "2023-06-01",
  beta_features? : Array[String] = [],
  supported_urls? : Array[@provider.SupportedUrlRule] = [
    @provider.SupportedUrlRule::http("image/*"),
    @provider.SupportedUrlRule::http("application/pdf"),
  ],
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
) -> AnthropicProvider raise {
  create_anthropic(
    api_key~,
    auth_token~,
    base_url~,
    provider_name~,
    headers~,
    anthropic_version~,
    beta_features~,
    supported_urls~,
    idle_timeout_ms~,
    http_transport?,
    api_key_environment_variable?,
    id_generator?,
  )
}

///|
/// Select the protocol-level Messages model used by provider adapters.
pub fn AnthropicProvider::messages_wire(
  self : AnthropicProvider,
  model_id : String,
) -> AnthropicMessagesModel {
  {
    provider_name: self.provider_name,
    api_key: self.api_key,
    auth_token: self.auth_token,
    api_key_environment_variable: self.api_key_environment_variable,
    base_url: self.base_url,
    model_id,
    headers: @provider_utils.copy_headers(self.headers),
    anthropic_version: self.anthropic_version,
    beta_features: copy_strings(self.beta_features),
    supported_url_rules: self.supported_url_rules.copy(),
    idle_timeout_ms: self.idle_timeout_ms,
    id_generator: self.id_generator,
    http_transport: self.http_transport,
  }
}

///|
/// Select a Messages API language model.
pub fn AnthropicProvider::chat(
  self : AnthropicProvider,
  model_id : String,
) -> AnthropicLanguageModelV4 {
  AnthropicLanguageModelV4::new(self.messages_wire(model_id))
}

///|
/// Explicit wire alias for code that extends the Messages protocol adapter.
pub fn AnthropicProvider::chat_wire(
  self : AnthropicProvider,
  model_id : String,
) -> AnthropicMessagesModel {
  self.messages_wire(model_id)
}

///|
/// Select a model using the AI SDK `messages` naming.
pub fn AnthropicProvider::messages(
  self : AnthropicProvider,
  model_id : String,
) -> AnthropicLanguageModelV4 {
  self.chat(model_id)
}

///|
/// Select a model using an explicit language-model name.
pub fn AnthropicProvider::language_model(
  self : AnthropicProvider,
  model_id : String,
) -> AnthropicLanguageModelV4 {
  self.messages(model_id)
}

///|
/// One language model served through the Anthropic Messages API.
pub struct AnthropicMessagesModel {
  priv provider_name : String
  priv api_key : ApiKey
  priv auth_token : String
  priv api_key_environment_variable : String?
  priv base_url : String
  priv model_id : String
  priv headers : Map[String, String]
  priv anthropic_version : String
  priv beta_features : Array[String]
  priv supported_url_rules : Array[@provider.SupportedUrlRule]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct the low-level Anthropic Messages wire model directly.
pub fn anthropic_messages(
  model_id : String,
  api_key? : String = "",
  auth_token? : String = "",
  base_url? : String = "",
  headers? : Map[String, String] = Map([]),
  anthropic_version? : String = "2023-06-01",
  beta_features? : Array[String] = [],
  supported_urls? : Array[@provider.SupportedUrlRule] = [
    @provider.SupportedUrlRule::http("image/*"),
    @provider.SupportedUrlRule::http("application/pdf"),
  ],
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
) -> AnthropicMessagesModel raise {
  create_anthropic(
    api_key~,
    auth_token~,
    base_url~,
    headers~,
    anthropic_version~,
    beta_features~,
    supported_urls~,
    idle_timeout_ms~,
    http_transport?,
    api_key_environment_variable?,
    id_generator?,
  ).messages_wire(model_id)
}

///|
/// Construct the default V4 Anthropic language model directly.
pub fn anthropic(
  model_id : String,
  api_key? : String = "",
  auth_token? : String = "",
  base_url? : String = "",
  headers? : Map[String, String] = Map([]),
  anthropic_version? : String = "2023-06-01",
  beta_features? : Array[String] = [],
  supported_urls? : Array[@provider.SupportedUrlRule] = [
    @provider.SupportedUrlRule::http("image/*"),
    @provider.SupportedUrlRule::http("application/pdf"),
  ],
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
) -> AnthropicLanguageModelV4 raise {
  AnthropicLanguageModelV4::new(
    anthropic_messages(
      model_id,
      api_key~,
      auth_token~,
      base_url~,
      headers~,
      anthropic_version~,
      beta_features~,
      supported_urls~,
      idle_timeout_ms~,
      http_transport?,
      api_key_environment_variable?,
      id_generator?,
    ),
  )
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
  request_features : Array[String],
) -> Array[String] {
  let features = copy_strings(self.beta_features)
  for feature in request_features {
    append_unique(features, feature)
  }
  features
}

///|
fn AnthropicMessagesModel::request_headers(
  self : AnthropicMessagesModel,
  call_headers : Map[String, String],
  request_beta_features~ : Array[String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["anthropic-version"] = self.anthropic_version
  for
    entry in anthropic_authentication_headers(
      self.api_key,
      self.auth_token,
      self.api_key_environment_variable,
    ).iter2() {
    let (key, value) = entry
    headers[key] = value
  }
  let beta_features = self.request_beta_features(request_beta_features)
  if beta_features.length() > 0 {
    headers["anthropic-beta"] = beta_features.join(",")
  }
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      [
        if self.provider_name.has_prefix("minimax") {
          "moonai/minimax/\{VERSION}"
        } else {
          "moonai/anthropic/\{VERSION}"
        },
      ],
    ),
    call_headers,
  )
}

///|
pub impl @provider.ChatModel for AnthropicMessagesModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ChatModel for AnthropicMessagesModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ChatModel for AnthropicMessagesModel with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.supported_url_rules.copy()
}

///|
/// Generate a complete Anthropic response. The Messages adapter currently
/// accumulates its streaming endpoint so it shares the same normalized result.
pub impl @provider.ChatModel for AnthropicMessagesModel with fn generate(
  self,
  options,
) {
  self.generate_messages(options)
}

///|
pub impl @provider.ChatModel for AnthropicMessagesModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_messages(options, on_event)
}
