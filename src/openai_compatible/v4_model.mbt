///|
/// Native V4 boundary for an OpenAI-compatible Chat Completions model.
/// Provider-specific request and response behavior remains in this package.
pub struct OpenAICompatibleLanguageModelV4 {
  model : OpenAICompatibleChatModel
}

///|
/// Construct a V4 OpenAI-compatible model.
pub fn OpenAICompatibleLanguageModelV4::new(
  model : OpenAICompatibleChatModel,
) -> OpenAICompatibleLanguageModelV4 {
  { model, }
}

///|
fn compatible_v4_chat_options(
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
fn compatible_v4_response_json(response : @provider.ResponseMetadata?) -> Json? {
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
fn compatible_v4_raw_usage(response : Json?) -> Json? {
  match response {
    Some({ "usage": usage, .. }) if !(usage is Null) => Some(usage)
    _ => None
  }
}

///|
fn compatible_v4_raw_finish_reason(response : Json?) -> String? {
  match response {
    Some({ "choices": [{ "finish_reason": String(value), .. }, ..], .. }) =>
      Some(value)
    _ => None
  }
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider()
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id()
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleLanguageModelV4 with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.model.supported_urls()
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let response = self.model.generate_chat(compatible_v4_chat_options(options))
  let raw = compatible_v4_response_json(response.response)
  @provider.LanguageModelV4GenerateResult::from_chat_response(response).with_usage_and_finish_reason(
    match compatible_v4_raw_usage(raw) {
      Some(_) =>
        @provider.LanguageModelV4Usage::from_usage(response.usage).with_raw(
          compatible_v4_raw_usage(raw),
        )
      None => @provider.LanguageModelV4Usage::unknown()
    },
    @provider.LanguageModelV4FinishReason::from_finish_reason(
      response.finish_reason,
    ).with_raw(compatible_v4_raw_finish_reason(raw)),
  )
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let chat_options = (self.model.transform_chat_options)(
    compatible_v4_chat_options(options),
  )
  let prepared = prepare_compatible_chat_request(
    self.model.model_id,
    chat_options,
    self.model.preserve_reasoning,
    self.model.include_usage,
    true,
    self.model.provider_name,
    self.model.supports_structured_outputs,
    self.model.supports_top_k,
    self.model.supports_frequency_penalty,
    self.model.prompt_converter,
  )
  let metadata_extractor = self.model.metadata_extractor
  let decoder = OpenAICompatibleStreamDecoder::new(
    include_raw_chunks=chat_options.include_raw_chunks,
    provider_name=self.model.provider_name,
    metadata_key=prepared.metadata_key,
    error_structure=self.model.error_structure,
    metadata_extractor?,
    convert_usage=self.model.convert_usage,
    id_generator=self.model.id_generator,
    generate_reasoning_ids=self.model.generate_reasoning_ids,
  )
  let warnings = prepared.warnings
  let request_body = (self.model.transform_request_body)(prepared.body)
  let cancellation_token = chat_options.cancellation_token
  let result = @provider_utils.post_json_sse(
    provider_name=self.model.provider_name,
    url=self.model.chat_completions_url(),
    headers=@provider_utils.merge_headers(
      self.model.request_headers(),
      chat_options.headers,
    ),
    body=request_body,
    idle_timeout_ms=self.model.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=chat_options.retry_policy,
    cancellation_token?,
    error_to_message=json => self.model.error_structure.message(json),
    is_retryable_response=(status_code, error) => {
      self.model.error_structure.retryable(status_code, error)
    },
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
