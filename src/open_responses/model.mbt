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
) -> &@provider.LanguageModelV4 {
  let model = OpenResponsesLanguageModelV4::new(self.responses_wire(model_id))
  model as &@provider.LanguageModelV4
}

///|
/// AI SDK-style camel-case spelling for `language_model`.
pub fn OpenResponsesProvider::languageModel(
  self : OpenResponsesProvider,
  model_id : String,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
fn OpenResponsesProvider::responses_wire(
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
/// A model served through the Open Responses protocol.
priv struct OpenResponsesLanguageModel {
  provider_name : String
  provider_options_name : String
  url : String
  api_key : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  id_generator : @provider_utils.IdGenerator
  http_transport : &@provider_utils.HttpTransport
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
