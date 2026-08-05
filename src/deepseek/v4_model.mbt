///|
/// DeepSeek's native V4 boundary. Request preparation and SSE decoding stay
/// in the DeepSeek package so reasoning and usage behavior remain provider
/// specific.
pub struct DeepSeekLanguageModelV4 {
  model : DeepSeekChatModel
}

///|
/// Construct a V4 DeepSeek model.
pub fn DeepSeekLanguageModelV4::new(
  model : DeepSeekChatModel,
) -> DeepSeekLanguageModelV4 {
  { model, }
}

///|
fn deepseek_v4_raw_usage(json : Json) -> Json? {
  match json {
    { "usage": usage, .. } if !(usage is Null) => Some(usage)
    _ => None
  }
}

///|
fn deepseek_v4_raw_finish_reason(json : Json) -> String? {
  match json {
    { "choices": [{ "finish_reason": String(value), .. }, ..], .. } =>
      Some(value)
    _ => None
  }
}

///|
pub impl @provider.LanguageModelV4 for DeepSeekLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for DeepSeekLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider()
}

///|
pub impl @provider.LanguageModelV4 for DeepSeekLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id()
}

///|
pub impl @provider.LanguageModelV4 for DeepSeekLanguageModelV4 with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.model.supported_urls()
}

///|
pub impl @provider.LanguageModelV4 for DeepSeekLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let chat_options = options.to_chat_call_options()
  let prepared = prepare_deepseek_request(
    self.model.model_id,
    chat_options,
    self.model.provider_name,
    false,
    self.model.supports_thinking,
    self.model.supports_structured_outputs,
  )
  let cancellation_token = chat_options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.model.provider_name,
    url=self.model.chat_url(),
    headers=self.model.request_headers(chat_options),
    body=prepared.body,
    timeout_ms=self.model.idle_timeout_ms,
    retry_policy=chat_options.retry_policy,
    cancellation_token?,
    error_to_message=deepseek_error_message,
    transport=self.model.http_transport,
  )
  let decoded = decode_deepseek_chat_response(
    response.value,
    provider_name=self.model.provider_name,
    id_generator=self.model.id_generator,
  )
  let normalized = decoded
    .with_diagnostics(
      None,
      decoded.response,
      decoded.provider_metadata,
      prepared.warnings,
    )
    .with_transport(response.request, response.response)
  @provider.LanguageModelV4GenerateResult::from_chat_response(normalized).with_usage_and_finish_reason(
    deepseek_v4_usage_from_raw(deepseek_v4_raw_usage(response.value)),
    deepseek_v4_finish_reason_from_raw(
      deepseek_v4_raw_finish_reason(response.value),
    ),
  )
}

///|
pub impl @provider.LanguageModelV4 for DeepSeekLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let chat_options = options.to_chat_call_options()
  let prepared = prepare_deepseek_request(
    self.model.model_id,
    chat_options,
    self.model.provider_name,
    true,
    self.model.supports_thinking,
    self.model.supports_structured_outputs,
  )
  let decoder = DeepSeekStreamDecoder::new(
    include_raw_chunks=chat_options.include_raw_chunks,
    provider_name=self.model.provider_name,
    id_generator=self.model.id_generator,
  )
  let warnings = prepared.warnings
  let cancellation_token = chat_options.cancellation_token
  let result = @provider_utils.post_json_sse(
    provider_name=self.model.provider_name,
    url=self.model.chat_url(),
    headers=self.model.request_headers(chat_options),
    body=prepared.body,
    idle_timeout_ms=self.model.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=chat_options.retry_policy,
    cancellation_token?,
    error_to_message=deepseek_error_message,
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
