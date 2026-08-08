///|
/// Official OpenAI Realtime V4 provider adapter.
pub struct OpenAIRealtimeModel {
  priv provider_name : String
  priv base_url : String
  priv model_id : String
  priv api_key : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
fn openai_realtime_model(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> OpenAIRealtimeModel {
  {
    provider_name: "\{provider_name}.realtime",
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
    api_key,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn OpenAIRealtimeModel::request_headers(
  self : OpenAIRealtimeModel,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([
    ("Content-Type", "application/json"),
    ("Accept-Encoding", "identity"),
  ])
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    ["moonai/openai/\{VERSION}"],
  )
}

///|
fn OpenAIRealtimeModel::client_secrets_url(
  self : OpenAIRealtimeModel,
) -> String {
  @provider_utils.append_path(self.base_url, "/realtime/client_secrets")
}

///|
fn OpenAIRealtimeModel::client_websocket_url(
  self : OpenAIRealtimeModel,
) -> String raise {
  let authority = @provider_utils.url_authority(self.base_url).unwrap_or_else(() => {
    fail("OpenAI realtime requires an absolute base URL")
  })
  @provider_utils.append_query("wss://\{authority}/v1/realtime", {
    "model": self.model_id,
  })
}

///|
fn OpenAIRealtimeModel::create_client_secret_body(
  self : OpenAIRealtimeModel,
  options : @provider.RealtimeClientSecretOptions,
) -> Json raise {
  let session = match options.session_config {
    Some(config) => build_openai_realtime_session_config(config, self.model_id)
    None => ({ "type": "realtime", "model": self.model_id } : Json)
  }
  let fields : Map[String, Json] = Map([("session", session)])
  if options.expires_after_seconds is Some(seconds) {
    guard seconds > 0 else {
      fail("realtime expires_after_seconds must be greater than zero")
    }
    fields["expires_after"] = { "anchor": "created_at", "seconds": seconds }
  }
  Json::object(fields)
}

///|
async fn OpenAIRealtimeModel::create_client_secret(
  self : OpenAIRealtimeModel,
  options : @provider.RealtimeClientSecretOptions,
) -> @provider.RealtimeClientSecretResult {
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.client_secrets_url(),
    headers=self.request_headers(),
    body=self.create_client_secret_body(options),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=@provider.RetryPolicy::standard(),
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  @provider_utils.handle_json_response(response, value => {
    let token = @provider_utils.json_string_field(value, "value").unwrap_or_else(() => {
        fail("OpenAI realtime response is missing value")
      },
    )
    let expires_at = @provider_utils.json_int_field_opt(value, "expires_at")
    @provider.RealtimeClientSecretResult::new(
      token~,
      url=self.client_websocket_url(),
      expires_at?,
    )
  })
}

///|
pub impl @provider.RealtimeModelV4 for OpenAIRealtimeModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.RealtimeModelV4 for OpenAIRealtimeModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.RealtimeModelV4 for OpenAIRealtimeModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.RealtimeModelV4 for OpenAIRealtimeModel with fn do_create_client_secret(
  self,
  options,
) {
  self.create_client_secret(options)
}

///|
pub impl @provider.RealtimeModelV4 for OpenAIRealtimeModel with fn get_websocket_config(
  _self,
  token,
  url,
) {
  @provider.RealtimeWebSocketConfig::new(url~, protocols=[
    "realtime",
    "openai-insecure-api-key.\{token}",
  ])
}

///|
pub impl @provider.RealtimeModelV4 for OpenAIRealtimeModel with fn parse_server_event(
  _self,
  raw,
) {
  [parse_openai_realtime_server_event(raw)]
}

///|
pub impl @provider.RealtimeModelV4 for OpenAIRealtimeModel with fn serialize_client_event(
  self,
  event,
) {
  serialize_openai_realtime_client_event(event, self.model_id)
}

///|
pub impl @provider.RealtimeModelV4 for OpenAIRealtimeModel with fn build_session_config(
  self,
  config,
) {
  build_openai_realtime_session_config(config, self.model_id)
}

///|
pub impl @provider.RealtimeModelV4 for OpenAIRealtimeModel with fn get_health_check_response(
  _self,
  _raw,
) {
  None
}

///|
/// MoonBit representation of AI SDK's callable realtime factory.
pub struct OpenAIRealtimeFactory {
  priv provider_name : String
  priv base_url : String
  priv api_key : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
fn openai_realtime_factory(
  provider_name~ : String,
  base_url~ : String,
  api_key~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> OpenAIRealtimeFactory {
  {
    provider_name,
    base_url: @provider_utils.without_trailing_slash(base_url),
    api_key,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
  }
}

///|
/// Select a realtime model from this provider factory.
pub fn OpenAIRealtimeFactory::model(
  self : OpenAIRealtimeFactory,
  model_id : String,
) -> OpenAIRealtimeModel {
  openai_realtime_model(
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
/// Create a client token using AI SDK factory-level options.
pub async fn OpenAIRealtimeFactory::get_token(
  self : OpenAIRealtimeFactory,
  options : @provider.RealtimeFactoryTokenOptions,
) -> @provider.RealtimeClientSecretResult {
  let expires_after_seconds = options.expires_after_seconds
  let session_config = options.session_config
  let model = self.model(options.model) as &@provider.RealtimeModelV4
  model.do_create_client_secret(
    @provider.RealtimeClientSecretOptions::new(
      expires_after_seconds?,
      session_config?,
    ),
  )
}

///|
/// Camel-case alias for AI SDK's `getToken`.
pub async fn OpenAIRealtimeFactory::getToken(
  self : OpenAIRealtimeFactory,
  options : @provider.RealtimeFactoryTokenOptions,
) -> @provider.RealtimeClientSecretResult {
  self.get_token(options)
}

///|
/// Expose the provider-level V4 factory contract. The concrete `model` method
/// remains available for callers that need the provider-specific value, while
/// this implementation supplies the trait-object view used by registries and
/// generic integrations.
pub impl @provider.RealtimeFactoryV4 for OpenAIRealtimeFactory with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.RealtimeFactoryV4 for OpenAIRealtimeFactory with fn model(
  self,
  model_id,
) -> &@provider.RealtimeModelV4 {
  self.model(model_id) as &@provider.RealtimeModelV4
}

///|
pub impl @provider.RealtimeFactoryV4 for OpenAIRealtimeFactory with fn get_token(
  self,
  options,
) -> @provider.RealtimeModelV4ClientSecretResult {
  self.get_token(options)
}
