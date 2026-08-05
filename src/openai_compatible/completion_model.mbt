///|
/// A model using the OpenAI `/completions` wire protocol.
pub struct OpenAICompatibleCompletionModel {
  priv provider_name : String
  priv api_key : String
  priv api_key_environment_variable : String?
  priv base_url : String
  priv model_id : OpenAICompatibleCompletionModelId
  priv headers : Map[String, String]
  priv query_params : Map[String, String]
  priv include_usage : Bool
  priv error_structure : OpenAICompatibleErrorStructure
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct the protocol-level OpenAI-compatible completion model directly.
pub fn openai_compatible_completion_wire(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : OpenAICompatibleCompletionModelId,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  query_params? : Map[String, String] = Map([]),
  include_usage? : Bool = false,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
) -> OpenAICompatibleCompletionModel {
  {
    provider_name: "\{provider_name}.completion",
    api_key,
    api_key_environment_variable,
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
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
/// Construct an OpenAI-compatible completion language model through V4.
pub fn openai_compatible_completion(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : OpenAICompatibleCompletionModelId,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  query_params? : Map[String, String] = Map([]),
  include_usage? : Bool = false,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
) -> OpenAICompatibleCompletionLanguageModelV4 {
  OpenAICompatibleCompletionLanguageModelV4::new(
    openai_compatible_completion_wire(
      provider_name~,
      base_url~,
      model_id~,
      api_key~,
      headers~,
      query_params~,
      include_usage~,
      error_structure~,
      idle_timeout_ms~,
      http_transport?,
      api_key_environment_variable?,
    ),
  )
}

///|
fn OpenAICompatibleCompletionModel::completions_url(
  self : OpenAICompatibleCompletionModel,
) -> String {
  @provider_utils.append_query(
    @provider_utils.append_path(self.base_url, "/completions"),
    self.query_params,
  )
}

///|
fn OpenAICompatibleCompletionModel::request_headers(
  self : OpenAICompatibleCompletionModel,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  let api_key = match self.api_key_environment_variable {
    Some(environment_variable_name) =>
      Some(
        @provider_utils.load_api_key(
          self.api_key,
          environment_variable_name~,
          description=self.provider_name,
        ),
      )
    None if self.api_key != "" => Some(self.api_key)
    None => None
  }
  match api_key {
    Some(value) => headers["Authorization"] = "Bearer \{value}"
    None => ()
  }
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    [openai_compatible_user_agent_suffix(self.provider_name)],
  )
}

///|
pub impl @provider.CompletionModel for OpenAICompatibleCompletionModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.CompletionModel for OpenAICompatibleCompletionModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.CompletionModel for OpenAICompatibleCompletionModel with fn generate(
  self,
  options,
) {
  self.generate_completion(options)
}

///|
pub impl @provider.CompletionModel for OpenAICompatibleCompletionModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_completion(options, on_event)
}

///|
async fn OpenAICompatibleCompletionModel::generate_completion(
  self : OpenAICompatibleCompletionModel,
  options : @provider.CompletionOptions,
) -> @provider.CompletionResponse {
  let request_body = encode_completion_request(
    self.model_id,
    options,
    stream=false,
    provider_name=self.provider_name,
  )
  let option_resolution = resolve_compatible_options(
    options.provider_options,
    self.provider_name,
    completion_reserved_fields(),
  )
  let warnings = compatible_completion_request_warnings(
    options, option_resolution,
  )
  let request_headers = @provider_utils.merge_headers(
    self.request_headers(),
    options.headers,
  )
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.completions_url(),
    headers=request_headers,
    body=request_body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=json => self.error_structure.message(json),
    is_retryable_response=(status_code, error) => {
      self.error_structure.retryable(status_code, error)
    },
    transport=self.http_transport,
  )
  let decoded = decode_completion_response(
    response.value,
    error_structure=self.error_structure,
  )
  decoded
  .with_diagnostics(
    None,
    None,
    @provider_utils.provider_metadata_from_json(
      response.value,
      self.provider_name,
    ),
    warnings,
  )
  .with_transport(response.request, response.response)
}

///|
async fn OpenAICompatibleCompletionModel::stream_completion(
  self : OpenAICompatibleCompletionModel,
  options : @provider.CompletionOptions,
  on_event : async (@provider.StreamEvent) -> Unit,
) -> @provider.CompletionResponse {
  let decoder = OpenAICompatibleCompletionStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
    error_structure=self.error_structure,
  )
  let cancellation_token = options.cancellation_token
  let option_resolution = resolve_compatible_options(
    options.provider_options,
    self.provider_name,
    completion_reserved_fields(),
  )
  let warnings = compatible_completion_request_warnings(
    options, option_resolution,
  )
  let result = @provider_utils.post_json_sse(
    provider_name=self.provider_name,
    url=self.completions_url(),
    headers=@provider_utils.merge_headers(
      self.request_headers(),
      options.headers,
    ),
    body=encode_completion_request(
      self.model_id,
      options,
      include_usage=self.include_usage,
      provider_name=self.provider_name,
    ),
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=json => self.error_structure.message(json),
    is_retryable_response=(status_code, error) => {
      self.error_structure.retryable(status_code, error)
    },
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
