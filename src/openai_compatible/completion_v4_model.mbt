///|
/// Configuration for one OpenAI-compatible `/completions` model.
pub struct OpenAICompatibleCompletionConfig {
  priv provider_name : String
  priv api_key : String
  priv api_key_environment_variable : String?
  priv base_url : String
  priv headers : Map[String, String]
  priv query_params : Map[String, String]
  priv include_usage : Bool
  priv error_structure : OpenAICompatibleErrorStructure
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct `/completions` model configuration.
pub fn OpenAICompatibleCompletionConfig::new(
  provider_name~ : String,
  base_url~ : String,
  api_key? : String = "",
  api_key_environment_variable? : String,
  headers? : Map[String, String] = Map([]),
  query_params? : Map[String, String] = Map([]),
  include_usage? : Bool = false,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> OpenAICompatibleCompletionConfig {
  {
    provider_name,
    api_key,
    api_key_environment_variable,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    query_params: @provider_utils.copy_headers(query_params),
    include_usage,
    error_structure,
    idle_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// OpenAI-compatible `/completions` implementation of `LanguageModelV4`.
pub struct OpenAICompatibleCompletionLanguageModel {
  priv model_id_value : OpenAICompatibleCompletionModelId
  priv config : OpenAICompatibleCompletionConfig
}

///|
/// Construct an OpenAI-compatible completion language model.
pub fn OpenAICompatibleCompletionLanguageModel::new(
  model_id : OpenAICompatibleCompletionModelId,
  config : OpenAICompatibleCompletionConfig,
) -> OpenAICompatibleCompletionLanguageModel {
  { model_id_value: model_id, config }
}

///|
fn OpenAICompatibleCompletionLanguageModel::completions_url(
  self : OpenAICompatibleCompletionLanguageModel,
) -> String {
  @provider_utils.append_query(
    @provider_utils.append_path(self.config.base_url, "/completions"),
    self.config.query_params,
  )
}

///|
fn OpenAICompatibleCompletionLanguageModel::request_headers_with(
  self : OpenAICompatibleCompletionLanguageModel,
  extra_headers : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  let api_key = match self.config.api_key_environment_variable {
    Some(environment_variable_name) =>
      Some(
        @provider_utils.load_api_key(
          self.config.api_key,
          environment_variable_name~,
          description=self.config.provider_name,
        ),
      )
    None if self.config.api_key != "" => Some(self.config.api_key)
    None => None
  }
  if api_key is Some(value) {
    headers["Authorization"] = "Bearer \{value}"
  }
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.config.headers),
      [openai_compatible_user_agent_suffix(self.config.provider_name)],
    ),
    extra_headers,
  )
}

///|
fn compatible_completion_v4_warnings(
  options : @provider.LanguageModelV4CallOptions,
) -> Array[@provider.Warning] {
  let warnings : Array[@provider.Warning] = []
  if options.tools.length() > 0 {
    warnings.push(@provider.Warning::unsupported("tools"))
  }
  if options.tool_choice is Some(_) {
    warnings.push(@provider.Warning::unsupported("toolChoice"))
  }
  match options.response_format {
    @provider.V4ResponseText => ()
    @provider.V4ResponseJson(_) =>
      warnings.push(
        @provider.Warning::Unsupported(
          feature="responseFormat",
          details="JSON response format is not supported.",
        ),
      )
  }
  warnings
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleCompletionLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleCompletionLanguageModel with fn provider(
  self,
) -> String {
  self.config.provider_name
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleCompletionLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id_value
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleCompletionLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleCompletionLanguageModel with fn do_generate(
  self,
  options,
) {
  let prepared = prepare_compatible_completion_v4_request(
    self.model_id_value,
    options,
    self.config.provider_name,
    false,
    self.config.include_usage,
  )
  let response = @provider_utils.post_json(
    provider_name=self.config.provider_name,
    url=self.completions_url(),
    headers=self.request_headers_with(options.headers),
    body=prepared.body,
    timeout_ms=self.config.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=json => self.config.error_structure.message(json),
    is_retryable_response=(status_code, error) => {
      self.config.error_structure.retryable(status_code, error)
    },
    transport=self.config.http_transport,
  )
  let decoded = @provider_utils.handle_json_response(response, value => {
    decode_completion_response(value, self.config.error_structure)
  })
  {
    content: decoded.content,
    finish_reason: decoded.finish_reason,
    usage: decoded.usage,
    provider_metadata: @provider_utils.provider_metadata_from_json(
      response.value,
      self.config.provider_name,
    ),
    request: Some(response.request),
    response: Some(
      @provider.merge_response_metadata(decoded.response, response.response),
    ),
    warnings: prepared.warnings,
  }
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleCompletionLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  let prepared = prepare_compatible_completion_v4_request(
    self.model_id_value,
    options,
    self.config.provider_name,
    true,
    self.config.include_usage,
  )
  let decoder = OpenAICompatibleCompletionStreamDecoder::new(
    options.include_raw_chunks,
    self.config.provider_name,
    self.config.error_structure,
  )
  let warnings = prepared.warnings
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.config.provider_name,
    url=self.completions_url(),
    headers=self.request_headers_with(options.headers),
    body=prepared.body,
    idle_timeout_ms=self.config.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=json => self.config.error_structure.message(json),
    is_retryable_response=(status_code, error) => {
      self.config.error_structure.retryable(status_code, error)
    },
    start_events=[
      @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
    ],
    is_stream_error=event => event is @provider.V4Error(_),
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    finish_stream=() => decoder.finish_stream(),
    response=() => decoder.response_metadata_snapshot(),
    transport=self.config.http_transport,
    on_event~,
  )
  let response_metadata = @provider.merge_response_metadata(
    result.value,
    result.response,
  )
  @provider.LanguageModelV4StreamResult::new(
    Some(result.request),
    Some(response_metadata),
  )
}
