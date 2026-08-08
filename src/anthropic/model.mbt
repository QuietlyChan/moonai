///|
type ApiKey = String

///|
/// Customize the URL used by the Anthropic Messages endpoint.
///
/// The callback receives the normalized provider base URL and whether the
/// request is a streaming call. This mirrors the AI SDK provider hook and is
/// useful for gateways that route streaming and non-streaming requests
/// differently.
pub type AnthropicRequestUrlBuilder = (String, Bool) -> String

///|
/// The default versioned endpoint used by Anthropic Messages, FilesV4, and
/// SkillsV4 when no explicit or environment setting is supplied.
const ANTHROPIC_DEFAULT_BASE_URL : String = "https://api.anthropic.com/v1"

///|
fn default_anthropic_request_url(
  base_url : String,
  _is_streaming : Bool,
) -> String {
  @provider_utils.append_path(base_url, "/messages")
}

///|
fn identity_anthropic_request_body(body : Json, _betas : Array[String]) -> Json {
  body
}

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
  priv supports_native_structured_output : Bool
  priv supports_strict_tools : Bool
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
  priv transform_request_body : (Json, Array[String]) -> Json
  priv build_request_url : AnthropicRequestUrlBuilder
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
/// Read beta identifiers from a header map using the same case-insensitive,
/// comma-separated contract as AI SDK's Anthropic provider. Header-derived
/// identifiers are normalized to lower case because Anthropic treats beta
/// names case-insensitively and the TypeScript provider does the same before
/// merging them into the request set.
fn anthropic_header_beta_features(
  headers : Map[String, String],
) -> Array[String] {
  let features : Array[String] = []
  for entry in headers.iter2() {
    let (key, value) = entry
    if key.to_lower() == "anthropic-beta" {
      for raw_feature in value.split(",") {
        let feature = raw_feature.trim().to_owned()
        if !feature.is_empty() {
          append_unique(features, feature.to_lower())
        }
      }
    }
  }
  features
}

///|
/// Copy headers while removing all case variants of `anthropic-beta`. The
/// request builder writes one canonical header after merging all sources so a
/// caller cannot leave duplicate differently-cased entries in the transport
/// map.
fn without_anthropic_beta_header(
  headers : Map[String, String],
) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in headers.iter2() {
    let (key, value) = entry
    if key.to_lower() != "anthropic-beta" {
      result[key] = value
    }
  }
  result
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
fn resolve_anthropic_base_url(
  base_url : String?,
) -> String raise @provider.InvalidArgumentError {
  let validated = @provider_utils.validate_base_url(
    @provider_utils.load_optional_setting(
      base_url,
      environment_variable_name="ANTHROPIC_BASE_URL",
    ),
  )
  normalize_base_url(validated.unwrap_or(ANTHROPIC_DEFAULT_BASE_URL))
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
  base_url? : String,
  provider_name? : String = "anthropic.messages",
  headers? : Map[String, String] = Map([]),
  anthropic_version? : String = "2023-06-01",
  beta_features? : Array[String] = [],
  supported_urls? : Array[@provider.SupportedUrlRule] = [
    @provider.SupportedUrlRule::http("image/*"),
    @provider.SupportedUrlRule::http("application/pdf"),
  ],
  supports_native_structured_output? : Bool = true,
  supports_strict_tools? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
  transform_request_body? : (Json, Array[String]) -> Json = identity_anthropic_request_body,
  build_request_url? : AnthropicRequestUrlBuilder = default_anthropic_request_url,
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
    supports_native_structured_output,
    supports_strict_tools,
    idle_timeout_ms,
    id_generator: id_generator.unwrap_or(@provider_utils.generate_id),
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
    transform_request_body,
    build_request_url,
  }
}

///|
/// AI SDK-style camel-case spelling for `create_anthropic`.
pub fn createAnthropic(
  api_key? : String = "",
  auth_token? : String = "",
  base_url? : String,
  provider_name? : String = "anthropic.messages",
  headers? : Map[String, String] = Map([]),
  anthropic_version? : String = "2023-06-01",
  beta_features? : Array[String] = [],
  supported_urls? : Array[@provider.SupportedUrlRule] = [
    @provider.SupportedUrlRule::http("image/*"),
    @provider.SupportedUrlRule::http("application/pdf"),
  ],
  supports_native_structured_output? : Bool = true,
  supports_strict_tools? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
  transform_request_body? : (Json, Array[String]) -> Json = identity_anthropic_request_body,
  build_request_url? : AnthropicRequestUrlBuilder = default_anthropic_request_url,
) -> AnthropicProvider raise {
  create_anthropic(
    api_key~,
    auth_token~,
    base_url?,
    provider_name~,
    headers~,
    anthropic_version~,
    beta_features~,
    supported_urls~,
    supports_native_structured_output~,
    supports_strict_tools~,
    idle_timeout_ms~,
    http_transport?,
    api_key_environment_variable?,
    id_generator?,
    transform_request_body~,
    build_request_url~,
  )
}

///|
/// Construct the concrete Messages model behind the public V4 boundary.
fn AnthropicProvider::language_model_value(
  self : AnthropicProvider,
  model_id : String,
) -> AnthropicLanguageModel {
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
    supports_native_structured_output: self.supports_native_structured_output,
    supports_strict_tools: self.supports_strict_tools,
    idle_timeout_ms: self.idle_timeout_ms,
    id_generator: self.id_generator,
    http_transport: self.http_transport,
    transform_request_body: self.transform_request_body,
    build_request_url: self.build_request_url,
  }
}

///|
/// Select a Messages API language model.
pub fn AnthropicProvider::chat(
  self : AnthropicProvider,
  model_id : String,
) -> &@provider.LanguageModelV4 {
  let model = self.language_model_value(model_id)
  model as &@provider.LanguageModelV4
}

///|
/// Select a model using the AI SDK `messages` naming.
pub fn AnthropicProvider::messages(
  self : AnthropicProvider,
  model_id : String,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Select a model using an explicit language-model name.
pub fn AnthropicProvider::language_model(
  self : AnthropicProvider,
  model_id : String,
) -> &@provider.LanguageModelV4 {
  self.messages(model_id)
}

///|
/// AI SDK-style camel-case alias for `language_model`.
pub fn AnthropicProvider::languageModel(
  self : AnthropicProvider,
  model_id : String,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// One language model served through the Anthropic Messages API.
priv struct AnthropicLanguageModel {
  provider_name : String
  api_key : ApiKey
  auth_token : String
  api_key_environment_variable : String?
  base_url : String
  model_id : String
  headers : Map[String, String]
  anthropic_version : String
  beta_features : Array[String]
  supported_url_rules : Array[@provider.SupportedUrlRule]
  supports_native_structured_output : Bool
  supports_strict_tools : Bool
  idle_timeout_ms : Int
  id_generator : @provider_utils.IdGenerator
  http_transport : &@provider_utils.HttpTransport
  transform_request_body : (Json, Array[String]) -> Json
  build_request_url : AnthropicRequestUrlBuilder
}

///|
/// Construct the default V4 Anthropic language model directly.
pub fn anthropic(
  model_id : String,
  api_key? : String = "",
  auth_token? : String = "",
  base_url? : String,
  headers? : Map[String, String] = Map([]),
  anthropic_version? : String = "2023-06-01",
  beta_features? : Array[String] = [],
  supported_urls? : Array[@provider.SupportedUrlRule] = [
    @provider.SupportedUrlRule::http("image/*"),
    @provider.SupportedUrlRule::http("application/pdf"),
  ],
  supports_native_structured_output? : Bool = true,
  supports_strict_tools? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
  transform_request_body? : (Json, Array[String]) -> Json = identity_anthropic_request_body,
  build_request_url? : AnthropicRequestUrlBuilder = default_anthropic_request_url,
) -> &@provider.LanguageModelV4 raise {
  create_anthropic(
    api_key~,
    auth_token~,
    base_url?,
    headers~,
    anthropic_version~,
    beta_features~,
    supported_urls~,
    supports_native_structured_output~,
    supports_strict_tools~,
    idle_timeout_ms~,
    http_transport?,
    api_key_environment_variable?,
    id_generator?,
    transform_request_body~,
    build_request_url~,
  ).language_model(model_id)
}

///|
fn AnthropicLanguageModel::messages_url(
  self : AnthropicLanguageModel,
  is_streaming : Bool,
) -> String {
  (self.build_request_url)(self.base_url, is_streaming)
}

///|
fn AnthropicLanguageModel::request_beta_features(
  self : AnthropicLanguageModel,
  request_features : Array[String],
) -> Array[String] {
  let features = copy_strings(self.beta_features)
  for feature in request_features {
    append_unique(features, feature)
  }
  features
}

///|
/// Merge configured, request-prepared, and header-provided beta identifiers.
/// Header values are part of the provider contract as well: custom gateways
/// commonly advertise a beta through `anthropic-beta` without using provider
/// options, and request-body transforms must observe the complete set.
fn AnthropicLanguageModel::request_beta_features_with_headers(
  self : AnthropicLanguageModel,
  request_features : Array[String],
  call_headers : Map[String, String],
) -> Array[String] {
  let features = self.request_beta_features(request_features)
  for feature in anthropic_header_beta_features(self.headers) {
    append_unique(features, feature)
  }
  for feature in anthropic_header_beta_features(call_headers) {
    append_unique(features, feature)
  }
  features
}

///|
fn AnthropicLanguageModel::apply_request_body_transform(
  self : AnthropicLanguageModel,
  body : Json,
  request_beta_features : Array[String],
  call_headers : Map[String, String],
) -> Json {
  (self.transform_request_body)(
    body,
    self.request_beta_features_with_headers(request_beta_features, call_headers),
  )
}

///|
fn AnthropicLanguageModel::request_headers(
  self : AnthropicLanguageModel,
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
  let beta_features = self.request_beta_features_with_headers(
    request_beta_features, call_headers,
  )
  let configured_headers = without_anthropic_beta_header(self.headers)
  let call_headers_without_beta = without_anthropic_beta_header(call_headers)
  let merged = @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, configured_headers),
      [
        if self.provider_name.has_prefix("minimax") {
          "moonai/minimax/\{VERSION}"
        } else {
          "moonai/anthropic/\{VERSION}"
        },
      ],
    ),
    call_headers_without_beta,
  )
  if beta_features.length() > 0 {
    merged["anthropic-beta"] = beta_features.join(",")
  }
  merged
}
