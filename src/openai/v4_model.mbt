///|
/// OpenAI's Responses API implementation of the versioned language-model
/// contract.
priv struct OpenAIResponsesLanguageModelV4 {
  model : OpenAIResponsesModel
}

///|
/// Construct a V4 OpenAI Responses model.
fn OpenAIResponsesLanguageModelV4::new(
  model : OpenAIResponsesModel,
) -> OpenAIResponsesLanguageModelV4 {
  { model, }
}

///|
impl @provider.LanguageModelV4 for OpenAIResponsesLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for OpenAIResponsesLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider_name
}

///|
impl @provider.LanguageModelV4 for OpenAIResponsesLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id
}

///|
impl @provider.LanguageModelV4 for OpenAIResponsesLanguageModelV4 with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  [
    @provider.SupportedUrlRule::http("image/*"),
    @provider.SupportedUrlRule::http("application/pdf"),
  ]
}

///|
impl @provider.LanguageModelV4 for OpenAIResponsesLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let prepared = prepare_openai_v4_responses_request(
    self.model.model_id,
    options,
    self.model.provider_name,
    false,
  )
  let response = @provider_utils.post_json(
    provider_name=self.model.provider_name,
    url=self.model.url,
    headers=self.model.request_headers_with(options.headers),
    body=prepared.body,
    timeout_ms=self.model.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=openai_error_message,
    transport=self.model.http_transport,
  )
  let decoded = @provider_utils.handle_json_response(response, value => {
    decode_openai_responses_response(
      value,
      provider_name=self.model.provider_name,
      shell_provider_executed=prepared.shell_provider_executed,
      tool_name_mapping=prepared.tool_name_mapping,
      id_generator=self.model.id_generator,
      approval_tool_call_ids=openai_responses_approval_tool_call_ids(
        options.prompt,
        self.model.provider_name,
      ),
      web_search_tool_name?=prepared.web_search_tool_name,
    )
  })
  {
    content: decoded.content,
    finish_reason: decoded.finish_reason,
    usage: decoded.usage,
    provider_metadata: decoded.provider_metadata,
    request: Some(response.request),
    response: Some(
      @provider.merge_response_metadata(decoded.response, response.response),
    ),
    warnings: prepared.warnings,
  }
}

///|
impl @provider.LanguageModelV4 for OpenAIResponsesLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let prepared = prepare_openai_v4_responses_request(
    self.model.model_id,
    options,
    self.model.provider_name,
    true,
  )
  let create_runtime = () => {
    openai_responses_stream_runtime(
      self.model.provider_name,
      prepared.tool_name_mapping,
      prepared.shell_provider_executed,
      options.include_raw_chunks,
      store=match prepared.body {
        { "store": False, .. } => false
        _ => true
      },
      id_generator=self.model.id_generator,
      approval_tool_call_ids=openai_responses_approval_tool_call_ids(
        options.prompt,
        self.model.provider_name,
      ),
      web_search_tool_name?=prepared.web_search_tool_name,
    )
  }
  let (runtime, start_policy) = openai_responses_stream_runtime_with_policy(
    create_runtime,
  )
  let warnings = prepared.warnings
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.model.provider_name,
    url=self.model.url,
    headers=self.model.request_headers_with(options.headers),
    body=prepared.body,
    idle_timeout_ms=self.model.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=openai_error_message,
    start_events=[
      @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
    ],
    is_stream_error=event => event is @provider.V4Error(_),
    feed_line=raw => runtime.val.feed_line(raw),
    flush_buffered=() => runtime.val.flush_buffered(),
    finish_stream=() => runtime.val.finish_stream(),
    response=() => runtime.val.response_metadata_snapshot(),
    start_policy~,
    transport=self.model.http_transport,
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

///|
/// V4 language-model boundary for the official Chat Completions endpoint.
priv struct OpenAIChatLanguageModelV4 {
  model : OpenAIChatModel
}

///|
/// Construct the V4 wrapper for an official Chat Completions wire model.
fn OpenAIChatLanguageModelV4::new(
  model : OpenAIChatModel,
) -> OpenAIChatLanguageModelV4 {
  { model, }
}

///|
impl @provider.LanguageModelV4 for OpenAIChatLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for OpenAIChatLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider_name
}

///|
impl @provider.LanguageModelV4 for OpenAIChatLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id
}

///|
impl @provider.LanguageModelV4 for OpenAIChatLanguageModelV4 with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  [@provider.SupportedUrlRule::http("image/*")]
}

///|
impl @provider.LanguageModelV4 for OpenAIChatLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let prepared = prepare_openai_v4_chat_request(
    self.model.model_id,
    options,
    self.model.provider_name,
    false,
    self.model.include_usage,
  )
  let response = @provider_utils.post_json(
    provider_name=self.model.provider_name,
    url=self.model.chat_completions_url(),
    headers=self.model.request_headers_with(options.headers),
    body=prepared.body,
    timeout_ms=self.model.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=openai_error_message,
    transport=self.model.http_transport,
  )
  let decoded = @provider_utils.handle_json_response(response, value => {
    decode_openai_chat_response(
      value,
      self.model.provider_name,
      self.model.id_generator,
    )
  })
  {
    content: decoded.content,
    finish_reason: decoded.finish_reason,
    usage: decoded.usage,
    provider_metadata: decoded.provider_metadata,
    request: Some(response.request),
    response: Some(
      @provider.merge_response_metadata(decoded.response, response.response),
    ),
    warnings: prepared.warnings,
  }
}

///|
impl @provider.LanguageModelV4 for OpenAIChatLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let prepared = prepare_openai_v4_chat_request(
    self.model.model_id,
    options,
    self.model.provider_name,
    true,
    self.model.include_usage,
  )
  let create_decoder = () => {
    OpenAIChatStreamDecoder::new(
      include_raw_chunks=options.include_raw_chunks,
      provider_name=self.model.provider_name,
      id_generator=self.model.id_generator,
    )
  }
  let decoder = Ref(create_decoder())
  let start_policy = @provider_utils.SseStreamStartPolicy::new(
    is_accepted=() => false,
    is_output=() => decoder.val.has_output(),
    accepted_grace_ms=0,
    on_started=() => decoder.val.mark_stream_started(),
    on_retry=() => decoder.val = create_decoder(),
  )
  let warnings = prepared.warnings
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.model.provider_name,
    url=self.model.chat_completions_url(),
    headers=self.model.request_headers_with(options.headers),
    body=prepared.body,
    idle_timeout_ms=self.model.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=openai_error_message,
    start_events=[
      @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
    ],
    is_stream_error=event => event is @provider.V4Error(_),
    feed_line=raw => decoder.val.feed_line(raw),
    flush_buffered=() => decoder.val.flush_buffered(),
    finish_stream=() => decoder.val.finish_stream(),
    response=() => decoder.val.response_metadata_snapshot(),
    start_policy~,
    transport=self.model.http_transport,
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

///|
/// V4 language-model boundary for the official `/completions` endpoint.
priv struct OpenAICompletionLanguageModelV4 {
  model : OpenAICompletionModel
}

///|
/// Construct the V4 wrapper for an official `/completions` wire model.
fn OpenAICompletionLanguageModelV4::new(
  model : OpenAICompletionModel,
) -> OpenAICompletionLanguageModelV4 {
  { model, }
}

///|
fn openai_completion_v4_warnings(
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
      warnings.push(@provider.Warning::unsupported("responseFormat"))
  }
  warnings
}

///|

///|
impl @provider.LanguageModelV4 for OpenAICompletionLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for OpenAICompletionLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider_name
}

///|
impl @provider.LanguageModelV4 for OpenAICompletionLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id
}

///|
impl @provider.LanguageModelV4 for OpenAICompletionLanguageModelV4 with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
impl @provider.LanguageModelV4 for OpenAICompletionLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let prepared = prepare_openai_completion_v4_request(
    self.model.model_id,
    options,
    self.model.provider_name,
    false,
    self.model.include_usage,
  )
  let response = @provider_utils.post_json(
    provider_name=self.model.provider_name,
    url=self.model.completions_url(),
    headers=self.model.request_headers_with(options.headers),
    body=prepared.body,
    timeout_ms=self.model.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=openai_error_message,
    transport=self.model.http_transport,
  )
  let decoded = @provider_utils.handle_json_response(
    response, decode_openai_completion_response,
  )
  {
    content: decoded.content,
    finish_reason: decoded.finish_reason,
    usage: decoded.usage,
    provider_metadata: decoded.provider_metadata,
    request: Some(response.request),
    response: Some(
      @provider.merge_response_metadata(decoded.response, response.response),
    ),
    warnings: prepared.warnings,
  }
}

///|
impl @provider.LanguageModelV4 for OpenAICompletionLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let prepared = prepare_openai_completion_v4_request(
    self.model.model_id,
    options,
    self.model.provider_name,
    true,
    self.model.include_usage,
  )
  let create_decoder = () => {
    OpenAICompletionStreamDecoder::new(
      include_raw_chunks=options.include_raw_chunks,
    )
  }
  let decoder = Ref(create_decoder())
  let start_policy = @provider_utils.SseStreamStartPolicy::new(
    is_accepted=() => false,
    is_output=() => decoder.val.has_output(),
    accepted_grace_ms=0,
    on_started=() => decoder.val.mark_stream_started(),
    on_retry=() => decoder.val = create_decoder(),
  )
  let warnings = prepared.warnings
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.model.provider_name,
    url=self.model.completions_url(),
    headers=self.model.request_headers_with(options.headers),
    body=prepared.body,
    idle_timeout_ms=self.model.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=openai_error_message,
    start_events=[
      @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
    ],
    is_stream_error=event => event is @provider.V4Error(_),
    feed_line=raw => decoder.val.feed_line(raw),
    flush_buffered=() => decoder.val.flush_buffered(),
    finish_stream=() => decoder.val.finish_stream(),
    response=() => decoder.val.response_metadata_snapshot(),
    start_policy~,
    transport=self.model.http_transport,
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
