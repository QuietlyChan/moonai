///|
/// Official OpenAI Responses API model.
///
/// This type owns OpenAI-specific capability and option handling while reusing
/// the protocol decoder from `open_responses`.
pub struct OpenAIResponsesModel {
  priv provider_name : String
  priv url : String
  priv api_key : String
  priv model_id : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
fn OpenAIResponsesModel::request_headers(
  self : OpenAIResponsesModel,
  options : @provider.ChatCallOptions,
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
    options.headers,
  )
}

///|
async fn OpenAIResponsesModel::generate_responses(
  self : OpenAIResponsesModel,
  options : @provider.ChatCallOptions,
) -> @provider.ChatResponse {
  let prepared = prepare_openai_responses_request(
    self.model_id,
    options,
    self.provider_name,
    false,
  )
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.url,
    headers=self.request_headers(options),
    body=prepared.body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  let decoded = decode_openai_responses_response(
    response.value,
    provider_name=self.provider_name,
    tool_name_mapping=prepared.tool_name_mapping,
    id_generator=self.id_generator,
  )
  decoded
  .with_diagnostics(
    None,
    decoded.response,
    decoded.provider_metadata,
    prepared.warnings,
  )
  .with_transport(response.request, response.response)
}

///|
async fn OpenAIResponsesModel::stream_responses(
  self : OpenAIResponsesModel,
  options : @provider.ChatCallOptions,
  on_event : async (@provider.StreamEvent) -> Unit,
) -> @provider.ChatResponse {
  let prepared = prepare_openai_responses_request(
    self.model_id,
    options,
    self.provider_name,
    true,
  )
  let (record_metadata, build_provider_metadata) = openai_responses_stream_metadata(
    self.provider_name,
  )
  let guard_stream = openai_responses_stream_guard()
  let hosted_decoder = OpenAIResponsesHostedStreamDecoder::new(
    self.provider_name,
    prepared.tool_name_mapping,
    id_generator=self.id_generator,
  )
  let decoder = @open_responses.OpenResponsesStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    progressive_tool_calls=true,
    emit_failed_error=true,
    provider_name=self.provider_name,
    id_generator=self.id_generator,
    observe_json=record_metadata,
    validate_json=guard_stream,
    observe_events=json => hosted_decoder.observe(json),
    build_provider_metadata~,
    build_content=() => hosted_decoder.content(),
    use_built_content=true,
    has_extra_tool_calls=() => hosted_decoder.has_client_calls(),
  )
  let cancellation_token = options.cancellation_token
  let result = @provider_utils.post_json_sse(
    provider_name=self.provider_name,
    url=self.url,
    headers=self.request_headers(options),
    body=prepared.body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=openai_error_message,
    warnings=prepared.warnings,
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
    prepared.warnings,
  )
  .with_transport(result.request, result.response)
}

///|
pub impl @provider.ChatModel for OpenAIResponsesModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ChatModel for OpenAIResponsesModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ChatModel for OpenAIResponsesModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  [
    @provider.SupportedUrlRule::http("image/*"),
    @provider.SupportedUrlRule::http("application/pdf"),
  ]
}

///|
pub impl @provider.ChatModel for OpenAIResponsesModel with fn generate(
  self,
  options,
) {
  self.generate_responses(options)
}

///|
pub impl @provider.ChatModel for OpenAIResponsesModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_responses(options, on_event)
}
