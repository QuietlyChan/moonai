///|
/// Official OpenAI legacy `/completions` model.
priv struct OpenAICompletionModel {
  provider_name : String
  base_url : String
  model_id : String
  api_key : String
  headers : Map[String, String]
  include_usage : Bool
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn openai_completion_model(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key~ : String,
  headers~ : Map[String, String],
  include_usage~ : Bool,
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> OpenAICompletionModel {
  {
    provider_name: "\{provider_name}.completion",
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
    api_key,
    headers: @provider_utils.copy_headers(headers),
    include_usage,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn OpenAICompletionModel::completions_url(
  self : OpenAICompletionModel,
) -> String {
  @provider_utils.append_path(self.base_url, "/completions")
}

///|
fn OpenAICompletionModel::request_headers_with(
  self : OpenAICompletionModel,
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

///|
fn openai_completion_provider_metadata(json : Json) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([])
  match json {
    { "choices": [{ "logprobs": value, .. }, ..], .. } if !(value is Null) =>
      fields["logprobs"] = value
    _ => ()
  }
  Map([("openai", Json::object(fields))])
}

///|
priv struct OpenAICompletionDecodedResponse {
  content : Array[@provider.LanguageModelV4Content]
  finish_reason : @provider.LanguageModelV4FinishReason
  usage : @provider.LanguageModelV4Usage
  provider_metadata : Map[String, Json]
  response : @provider.ResponseMetadata?
}

///|
fn decode_openai_completion_response(
  json : Json,
) -> OpenAICompletionDecodedResponse raise {
  if openai_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI completion request failed: \{message}",
      data=json,
    )
  }
  let (text, raw_finish_reason) = match json {
    {
      "choices": [
        { "text": String(text), "finish_reason": String(reason), .. },
        ..,
      ],
      ..
    } => (text, Some(reason))
    { "choices": [{ "text": String(text), .. }, ..], .. } => (text, None)
    { "choices": [], .. } =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI completion response has no choices",
        data=json,
      )
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI completion response has no valid choice",
        data=json,
      )
  }
  let raw_usage = match json {
    { "usage": value, .. } if !(value is Null) => Some(value)
    _ => None
  }
  let response_metadata = @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(json, "id"),
    model?=@provider_utils.json_string_field(json, "model"),
    created?=@provider_utils.json_int_field_opt(json, "created"),
  )
  {
    content: [@provider.LanguageModelV4Content::text(text)],
    finish_reason: openai_chat_v4_finish_reason(raw_finish_reason),
    usage: openai_completion_v4_usage(raw_usage),
    provider_metadata: openai_completion_provider_metadata(json),
    response: if response_metadata.is_empty() {
      None
    } else {
      Some(response_metadata)
    },
  }
}
