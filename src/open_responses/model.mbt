///|
/// Configuration for one Open Responses compatible endpoint.
pub struct OpenResponsesProvider {
  priv provider_name : String
  priv url : String
  priv api_key : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create an Open Responses provider from an exact Responses API endpoint URL.
pub fn create_open_responses(
  provider_name~ : String,
  url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  id_generator? : @provider_utils.IdGenerator,
  http_transport? : &@provider_utils.HttpTransport,
) -> OpenResponsesProvider {
  {
    provider_name,
    url,
    api_key,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    id_generator: id_generator.unwrap_or(@provider_utils.generate_id),
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// AI SDK-style camel-case provider factory.
pub fn createOpenResponses(
  name~ : String,
  url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  id_generator? : @provider_utils.IdGenerator,
  http_transport? : &@provider_utils.HttpTransport,
) -> OpenResponsesProvider {
  create_open_responses(
    provider_name=name,
    url~,
    api_key~,
    headers~,
    idle_timeout_ms~,
    id_generator?,
    http_transport?,
  )
}

///|
/// Select an Open Responses language model.
pub fn OpenResponsesProvider::language_model(
  self : OpenResponsesProvider,
  model_id : String,
) -> OpenResponsesLanguageModelV4 {
  self.responses(model_id)
}

///|
/// AI SDK-style camel-case spelling for `language_model`.
pub fn OpenResponsesProvider::languageModel(
  self : OpenResponsesProvider,
  model_id : String,
) -> OpenResponsesLanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Select a model using the Responses API name.
pub fn OpenResponsesProvider::responses(
  self : OpenResponsesProvider,
  model_id : String,
) -> OpenResponsesLanguageModelV4 {
  OpenResponsesLanguageModelV4::new(self.responses_wire(model_id))
}

///|
/// Select the protocol-level model used to test or extend the wire adapter.
pub fn OpenResponsesProvider::responses_wire(
  self : OpenResponsesProvider,
  model_id : String,
) -> OpenResponsesLanguageModel {
  {
    provider_name: "\{self.provider_name}.responses",
    provider_options_name: self.provider_name,
    url: self.url,
    api_key: self.api_key,
    model_id,
    headers: @provider_utils.copy_headers(self.headers),
    idle_timeout_ms: self.idle_timeout_ms,
    id_generator: self.id_generator,
    http_transport: self.http_transport,
  }
}

///|
/// Short alias for `language_model`.
pub fn OpenResponsesProvider::model(
  self : OpenResponsesProvider,
  model_id : String,
) -> OpenResponsesLanguageModelV4 {
  self.responses(model_id)
}

///|
/// A model served through the Open Responses protocol.
pub struct OpenResponsesLanguageModel {
  priv provider_name : String
  priv provider_options_name : String
  priv url : String
  priv api_key : String
  priv model_id : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct the low-level Open Responses wire model directly.
pub fn open_responses_wire(
  model_id~ : String,
  provider_name~ : String,
  url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  id_generator? : @provider_utils.IdGenerator,
  http_transport? : &@provider_utils.HttpTransport,
) -> OpenResponsesLanguageModel {
  create_open_responses(
    provider_name~,
    url~,
    api_key~,
    headers~,
    idle_timeout_ms~,
    id_generator?,
    http_transport?,
  ).responses_wire(model_id)
}

///|
/// Construct the default V4 Open Responses language model directly.
pub fn open_responses(
  model_id~ : String,
  provider_name~ : String,
  url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  id_generator? : @provider_utils.IdGenerator,
  http_transport? : &@provider_utils.HttpTransport,
) -> OpenResponsesLanguageModelV4 {
  create_open_responses(
    provider_name~,
    url~,
    api_key~,
    headers~,
    idle_timeout_ms~,
    id_generator?,
    http_transport?,
  ).language_model(model_id)
}

///|
fn OpenResponsesLanguageModel::request_headers(
  self : OpenResponsesLanguageModel,
) -> Map[String, String] {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  if self.api_key != "" {
    headers["Authorization"] = "Bearer \{self.api_key}"
  }
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    ["moonai/open-responses/\{VERSION}"],
  )
}

///|
pub impl @provider.ChatModel for OpenResponsesLanguageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.ChatModel for OpenResponsesLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.ChatModel for OpenResponsesLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  [@provider.SupportedUrlRule::http("image/*")]
}

///|
pub impl @provider.ChatModel for OpenResponsesLanguageModel with fn generate(
  self,
  options,
) {
  self.generate_responses(options)
}

///|
pub impl @provider.ChatModel for OpenResponsesLanguageModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_responses(options, on_event)
}
