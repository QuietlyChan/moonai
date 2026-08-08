///|
/// Official OpenAI Chat Completions model.
priv struct OpenAIChatModel {
  provider_name : String
  base_url : String
  api_key : String
  model_id : String
  headers : Map[String, String]
  include_usage : Bool
  idle_timeout_ms : Int
  id_generator : @provider_utils.IdGenerator
  http_transport : &@provider_utils.HttpTransport
}

///|
fn OpenAIChatModel::chat_completions_url(self : OpenAIChatModel) -> String {
  @provider_utils.append_path(self.base_url, "/chat/completions")
}

///|
fn OpenAIChatModel::request_headers_with(
  self : OpenAIChatModel,
  extra_headers : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      ["moonai/openai/\{VERSION}"],
    ),
    extra_headers,
  )
}
