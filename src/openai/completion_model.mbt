///|
/// Official OpenAI legacy `/completions` model.
pub struct OpenAICompletionModel {
  priv provider_name : String
  priv base_url : String
  priv model_id : String
  priv api_key : String
  priv headers : Map[String, String]
  priv include_usage : Bool
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
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
fn OpenAICompletionModel::request_headers(
  self : OpenAICompletionModel,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    ["moonai/openai/\{VERSION}"],
  )
}

///|
fn openai_completion_request(
  model_id : String,
  call_options : @provider.CompletionOptions,
  provider_options : OpenAICompletionOptions,
  stream : Bool,
  include_usage : Bool,
) -> Json {
  let suffix = match provider_options.suffix {
    Some(value) => Some(value)
    None => call_options.suffix
  }
  Json::object(
    Map(
      [
        ("model", Json::string(model_id)),
        ("prompt", Json::string(call_options.prompt)),
        ..if stream {
          [("stream", Json::boolean(true))]
        },
        ..if stream && include_usage {
          [("stream_options", ({ "include_usage": true } : Json))]
        },
        ..if suffix is Some(value) {
          [("suffix", Json::string(value))]
        },
        ..if provider_options.echo is Some(value) {
          [("echo", Json::boolean(value))]
        },
        ..if provider_options.logit_bias is Some(value) {
          [("logit_bias", value)]
        },
        ..if provider_options.logprobs is Some(value) {
          [("logprobs", Json::number(value.to_double()))]
        },
        ..if provider_options.user is Some(value) {
          [("user", Json::string(value))]
        },
        ..if call_options.max_output_tokens is Some(value) {
          [("max_tokens", Json::number(value.to_double()))]
        },
        ..if call_options.temperature is Some(value) {
          [("temperature", Json::number(value))]
        },
        ..if call_options.top_p is Some(value) {
          [("top_p", Json::number(value))]
        },
        ..if call_options.frequency_penalty is Some(value) {
          [("frequency_penalty", Json::number(value))]
        },
        ..if call_options.presence_penalty is Some(value) {
          [("presence_penalty", Json::number(value))]
        },
        ..if call_options.seed is Some(value) {
          [("seed", Json::number(value.to_double()))]
        },
        ..if call_options.stop_sequences.length() > 0 {
          [
            (
              "stop",
              Json::array(
                [
                  for stop in call_options.stop_sequences => Json::string(stop)
                ],
              ),
            ),
          ]
        },
      ],
    ),
  )
}

///|
fn openai_completion_warnings(
  call_options : @provider.CompletionOptions,
  parsed : ParsedOpenAICompletionOptions,
) -> Array[@provider.Warning] {
  let warnings = parsed.warnings.copy()
  if call_options.top_k is Some(_) {
    warnings.push(@provider.Warning::unsupported("topK"))
  }
  warnings
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
fn decode_openai_completion_response(
  json : Json,
) -> @provider.CompletionResponse raise {
  if openai_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI completion request failed: \{message}",
      data=json,
    )
  }
  let (text, finish_reason) = match json {
    {
      "choices": [
        { "text": String(text), "finish_reason": String(reason), .. },
        ..,
      ],
      ..
    } => (text, @provider.FinishReason::from_openai(reason))
    { "choices": [{ "text": String(text), .. }, ..], .. } =>
      (text, @provider.Stop)
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
  let usage = match json {
    { "usage": value, .. } if !(value is Null) => openai_completion_usage(value)
    _ => @provider.Usage::zero()
  }
  @provider.CompletionResponse::new(text, usage, finish_reason)
}

///|
pub impl @provider.CompletionModel for OpenAICompletionModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.CompletionModel for OpenAICompletionModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.CompletionModel for OpenAICompletionModel with fn generate(
  self,
  call_options,
) {
  self.generate_completion(call_options)
}

///|
pub impl @provider.CompletionModel for OpenAICompletionModel with fn stream(
  self,
  call_options,
  on_event,
) {
  self.stream_completion(call_options, on_event)
}

///|
async fn OpenAICompletionModel::generate_completion(
  self : OpenAICompletionModel,
  call_options : @provider.CompletionOptions,
) -> @provider.CompletionResponse {
  let parsed = parse_openai_completion_options(call_options, self.provider_name)
  let warnings = openai_completion_warnings(call_options, parsed)
  let cancellation_token = call_options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.completions_url(),
    headers=@provider_utils.merge_headers(
      self.request_headers(),
      call_options.headers,
    ),
    body=openai_completion_request(
      self.model_id,
      call_options,
      parsed.options,
      false,
      self.include_usage,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=call_options.retry_policy,
    cancellation_token?,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  decode_openai_completion_response(response.value)
  .with_diagnostics(
    None,
    None,
    openai_completion_provider_metadata(response.value),
    warnings,
  )
  .with_transport(response.request, response.response)
}

///|
async fn OpenAICompletionModel::stream_completion(
  self : OpenAICompletionModel,
  call_options : @provider.CompletionOptions,
  on_event : async (@provider.StreamEvent) -> Unit,
) -> @provider.CompletionResponse {
  let parsed = parse_openai_completion_options(call_options, self.provider_name)
  let warnings = openai_completion_warnings(call_options, parsed)
  let decoder = OpenAICompletionStreamDecoder::new(
    include_raw_chunks=call_options.include_raw_chunks,
  )
  let cancellation_token = call_options.cancellation_token
  let result = @provider_utils.post_json_sse(
    provider_name=self.provider_name,
    url=self.completions_url(),
    headers=@provider_utils.merge_headers(
      self.request_headers(),
      call_options.headers,
    ),
    body=openai_completion_request(
      self.model_id,
      call_options,
      parsed.options,
      true,
      self.include_usage,
    ),
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=call_options.retry_policy,
    cancellation_token?,
    error_to_message=openai_error_message,
    warnings~,
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    response=() => decoder.response(),
    transport=self.http_transport,
    on_event~,
  )
  result.value
  .with_diagnostics(
    None,
    result.value.response,
    result.value.provider_metadata,
    warnings,
  )
  .with_transport(result.request, result.response)
}
