///|
/// OpenAI's Responses API implementation of the versioned language-model
/// contract.
pub struct OpenAIResponsesLanguageModelV4 {
  model : OpenAIResponsesModel
}

///|
/// Construct a V4 OpenAI Responses model.
pub fn OpenAIResponsesLanguageModelV4::new(
  model : OpenAIResponsesModel,
) -> OpenAIResponsesLanguageModelV4 {
  { model, }
}

///|
pub impl @provider.LanguageModelV4 for OpenAIResponsesLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for OpenAIResponsesLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider()
}

///|
pub impl @provider.LanguageModelV4 for OpenAIResponsesLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id()
}

///|
pub impl @provider.LanguageModelV4 for OpenAIResponsesLanguageModelV4 with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.model.supported_urls()
}

///|
fn openai_v4_response_json(response : @provider.ResponseMetadata?) -> Json? {
  match response {
    Some(metadata) =>
      match metadata.body {
        Some(body) =>
          try @json.parse(body) catch {
            _ => None
          } noraise {
            value => Some(value)
          }
        None => None
      }
    None => None
  }
}

///|
fn openai_v4_chat_options(
  options : @provider.LanguageModelV4CallOptions,
) -> @provider.ChatCallOptions {
  @provider.ChatCallOptions::new(
    options.prompt.to_language_model_prompt(),
    tools=options.tools,
    tool_choice?=options.tool_choice,
    response_format=options.response_format,
    reasoning_effort=options.reasoning_effort,
    max_output_tokens?=options.max_output_tokens,
    temperature?=options.temperature,
    top_p?=options.top_p,
    top_k?=options.top_k,
    frequency_penalty?=options.frequency_penalty,
    presence_penalty?=options.presence_penalty,
    seed?=options.seed,
    stop_sequences=options.stop_sequences,
    include_raw_chunks=options.include_raw_chunks,
    headers=options.headers,
    provider_options=options.provider_options,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}

///|
pub impl @provider.LanguageModelV4 for OpenAIResponsesLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let response = self.model.generate_responses(openai_v4_chat_options(options))
  let raw = openai_v4_response_json(response.response)
  let raw_usage = match raw {
    Some({ "usage": usage, .. }) if !(usage is Null) => Some(usage)
    _ => None
  }
  let raw_finish_reason = match raw {
    Some({ "incomplete_details": { "reason": String(value), .. }, .. }) =>
      Some(value)
    Some({ "status": "failed", "error": { "code": String(value), .. }, .. }) =>
      Some(value)
    Some({ "status": "failed", .. }) => Some("failed")
    _ => None
  }
  @provider.LanguageModelV4GenerateResult::from_chat_response(response).with_usage_and_finish_reason(
    @provider.LanguageModelV4Usage::from_token_usage_json(raw_usage),
    @provider.LanguageModelV4FinishReason::from_finish_reason(
      response.finish_reason,
    ).with_raw(raw_finish_reason),
  )
}

///|
pub impl @provider.LanguageModelV4 for OpenAIResponsesLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let chat_options = openai_v4_chat_options(options)
  let prepared = prepare_openai_responses_request(
    self.model.model_id,
    chat_options,
    self.model.provider_name,
    true,
  )
  let (record_metadata, build_provider_metadata) = openai_responses_stream_metadata(
    self.model.provider_name,
  )
  let guard_stream = openai_responses_stream_guard()
  let hosted_decoder = OpenAIResponsesHostedStreamDecoder::new(
    self.model.provider_name,
    prepared.tool_name_mapping,
    id_generator=self.model.id_generator,
  )
  let decoder = @open_responses.OpenResponsesStreamDecoder::new(
    include_raw_chunks=chat_options.include_raw_chunks,
    progressive_tool_calls=true,
    emit_failed_error=true,
    provider_name=self.model.provider_name,
    id_generator=self.model.id_generator,
    observe_json=record_metadata,
    validate_json=guard_stream,
    observe_events=json => hosted_decoder.observe(json),
    build_provider_metadata~,
    build_content=() => hosted_decoder.content(),
    use_built_content=true,
    has_extra_tool_calls=() => hosted_decoder.has_client_calls(),
  )
  let warnings = prepared.warnings
  let cancellation_token = chat_options.cancellation_token
  let result = @provider_utils.post_json_sse(
    provider_name=self.model.provider_name,
    url=self.model.url,
    headers=self.model.request_headers(chat_options),
    body=prepared.body,
    idle_timeout_ms=self.model.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=chat_options.retry_policy,
    cancellation_token?,
    error_to_message=openai_error_message,
    warnings~,
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    response=() => decoder.response(),
    transport=self.model.http_transport,
    on_event=event => {
      match event {
        @provider.StreamStart =>
          on_event(
            @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
          )
        @provider.Warning(_) => ()
        @provider.Finish(..) =>
          on_event(
            @provider.V4Finish(
              usage=decoder.v4_usage(),
              reason=decoder.v4_finish_reason(),
              provider_metadata=decoder.provider_metadata_snapshot(),
            ),
          )
        other =>
          on_event(
            @provider.LanguageModelV4StreamPart::from_stream_event(other),
          )
      }
    },
  )
  let response_metadata = @provider.merge_response_metadata(
    result.value.response,
    result.response,
  )
  @provider.LanguageModelV4StreamResult::new(
    Some(result.request),
    Some(response_metadata),
    usage=decoder.v4_usage(),
    finish_reason=decoder.v4_finish_reason(),
    provider_metadata=decoder.provider_metadata_snapshot(),
    warnings~,
  )
}

///|
/// V4 language-model boundary for the official Chat Completions endpoint.
pub struct OpenAIChatLanguageModelV4 {
  model : OpenAIChatModel
}

///|
/// Construct the V4 wrapper for an official Chat Completions wire model.
pub fn OpenAIChatLanguageModelV4::new(
  model : OpenAIChatModel,
) -> OpenAIChatLanguageModelV4 {
  { model, }
}

///|
pub impl @provider.LanguageModelV4 for OpenAIChatLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for OpenAIChatLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider()
}

///|
pub impl @provider.LanguageModelV4 for OpenAIChatLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id()
}

///|
pub impl @provider.LanguageModelV4 for OpenAIChatLanguageModelV4 with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.model.supported_urls()
}

///|
pub impl @provider.LanguageModelV4 for OpenAIChatLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let response = self.model.generate_chat(openai_v4_chat_options(options))
  let raw = openai_v4_response_json(response.response)
  let raw_usage = match raw {
    Some({ "usage": usage, .. }) if !(usage is Null) => Some(usage)
    _ => None
  }
  let raw_finish_reason = match raw {
    Some({ "choices": [{ "finish_reason": String(value), .. }, ..], .. }) =>
      Some(value)
    _ => None
  }
  @provider.LanguageModelV4GenerateResult::from_chat_response(response).with_usage_and_finish_reason(
    @provider.LanguageModelV4Usage::from_usage(response.usage).with_raw(
      raw_usage,
    ),
    @provider.LanguageModelV4FinishReason::from_finish_reason(
      response.finish_reason,
    ).with_raw(raw_finish_reason),
  )
}

///|
pub impl @provider.LanguageModelV4 for OpenAIChatLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let response = self.model.stream_chat(openai_v4_chat_options(options), event => {
    on_event(@provider.LanguageModelV4StreamPart::from_stream_event(event))
  })
  @provider.LanguageModelV4StreamResult::new(
    response.request,
    response.response,
    usage=@provider.LanguageModelV4Usage::from_usage(response.usage),
    finish_reason=@provider.LanguageModelV4FinishReason::from_finish_reason(
      response.finish_reason,
    ),
    provider_metadata=response.provider_metadata,
    warnings=response.warnings,
  )
}

///|
/// V4 language-model boundary for the official `/completions` endpoint.
pub struct OpenAICompletionLanguageModelV4 {
  model : OpenAICompletionModel
}

///|
/// Construct the V4 wrapper for an official `/completions` wire model.
pub fn OpenAICompletionLanguageModelV4::new(
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
    @provider.Text => ()
    @provider.JsonResponse(_) =>
      warnings.push(@provider.Warning::unsupported("responseFormat"))
  }
  warnings
}

///|
fn openai_completion_v4_options(
  options : @provider.LanguageModelV4CallOptions,
) -> @provider.CompletionOptions raise {
  let converted = @provider_utils.convert_to_completion_prompt(options.prompt)
  let stop_sequences = converted.stop_sequences.copy()
  for value in options.stop_sequences {
    stop_sequences.push(value)
  }
  @provider.CompletionOptions::new(
    converted.prompt,
    max_output_tokens?=options.max_output_tokens,
    temperature?=options.temperature,
    top_p?=options.top_p,
    top_k?=options.top_k,
    frequency_penalty?=options.frequency_penalty,
    presence_penalty?=options.presence_penalty,
    seed?=options.seed,
    stop_sequences~,
    include_raw_chunks=options.include_raw_chunks,
    headers=options.headers,
    provider_options=options.provider_options,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}

///|
fn append_openai_completion_warnings(
  extra : Array[@provider.Warning],
  existing : Array[@provider.Warning],
) -> Array[@provider.Warning] {
  let warnings = @provider.copy_warnings(extra)
  for warning in existing {
    warnings.push(warning)
  }
  warnings
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompletionLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompletionLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider()
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompletionLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id()
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompletionLanguageModelV4 with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompletionLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let wrapper_warnings = openai_completion_v4_warnings(options)
  let response = self.model.generate_completion(
    openai_completion_v4_options(options),
  )
  let response = response.with_diagnostics(
    response.request,
    response.response,
    response.provider_metadata,
    append_openai_completion_warnings(wrapper_warnings, response.warnings),
  )
  let raw = openai_v4_response_json(response.response)
  let raw_usage = match raw {
    Some({ "usage": usage, .. }) if !(usage is Null) => Some(usage)
    _ => None
  }
  let raw_finish_reason = match raw {
    Some({ "choices": [{ "finish_reason": String(value), .. }, ..], .. }) =>
      Some(value)
    _ => None
  }
  @provider.LanguageModelV4GenerateResult::from_completion_response(response).with_usage_and_finish_reason(
    @provider.LanguageModelV4Usage::from_usage(response.usage).with_raw(
      raw_usage,
    ),
    @provider.LanguageModelV4FinishReason::from_finish_reason(
      response.finish_reason,
    ).with_raw(raw_finish_reason),
  )
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompletionLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let wrapper_warnings = openai_completion_v4_warnings(options)
  let response = self.model.stream_completion(
    openai_completion_v4_options(options),
    event => {
      match event {
        @provider.StreamStart =>
          on_event(
            @provider.V4StreamStart(
              warnings=@provider.copy_warnings(wrapper_warnings),
            ),
          )
        other =>
          on_event(
            @provider.LanguageModelV4StreamPart::from_stream_event(other),
          )
      }
    },
  )
  let warnings = append_openai_completion_warnings(
    wrapper_warnings,
    response.warnings,
  )
  @provider.LanguageModelV4StreamResult::new(
    response.request,
    response.response,
    usage=@provider.LanguageModelV4Usage::from_usage(response.usage),
    finish_reason=@provider.LanguageModelV4FinishReason::from_finish_reason(
      response.finish_reason,
    ),
    provider_metadata=response.provider_metadata,
    warnings~,
  )
}
