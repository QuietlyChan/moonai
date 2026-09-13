///|
/// The self-contained Moonshot AI Chat Completions model.
///
/// Moonshot diverges from the OpenAI-compatible surface in enough places
/// (native max_completion_tokens, family-specific thinking controls, the
/// MFJS schema dialect, in-band typed stream errors) that it gets its own
/// request builder, message converter, and stream decoder.
priv struct MoonshotAIChatLanguageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : MoonshotAIChatModelId
  headers : Map[String, String]
  include_usage : Bool
  supports_structured_outputs : Bool
  idle_timeout_ms : Int
  id_generator : @provider_utils.IdGenerator
  http_transport : &@provider_utils.HttpTransport
}

///|
fn MoonshotAIChatLanguageModel::new(
  model_id~ : MoonshotAIChatModelId,
  provider_name~ : String,
  base_url~ : String,
  api_key~ : String,
  headers~ : Map[String, String],
  include_usage~ : Bool,
  supports_structured_outputs~ : Bool,
  idle_timeout_ms~ : Int,
  id_generator~ : @provider_utils.IdGenerator,
  http_transport~ : &@provider_utils.HttpTransport,
) -> MoonshotAIChatLanguageModel {
  {
    provider_name,
    api_key,
    base_url,
    model_id,
    headers,
    include_usage,
    supports_structured_outputs,
    idle_timeout_ms,
    id_generator,
    http_transport,
  }
}

///|
fn MoonshotAIChatLanguageModel::chat_url(
  self : MoonshotAIChatLanguageModel,
) -> String {
  @provider_utils.append_path(self.base_url, "/chat/completions")
}

///|
fn MoonshotAIChatLanguageModel::request_headers(
  self : MoonshotAIChatLanguageModel,
  overrides : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Authorization"] = "Bearer " + load_moonshot_api_key(self.api_key)
  let merged = @provider_utils.merge_headers(headers, self.headers)
  let merged = @provider_utils.merge_headers(merged, overrides)
  @provider_utils.with_user_agent_suffix(merged, [
    "moonai/moonshotai/\{VERSION}",
  ])
}

///|
impl @provider.LanguageModelV4 for MoonshotAIChatLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for MoonshotAIChatLanguageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
impl @provider.LanguageModelV4 for MoonshotAIChatLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
impl @provider.LanguageModelV4 for MoonshotAIChatLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  // Moonshot AI does not fetch external URLs; only ms:// file references
  // from the Moonshot Files API pass through natively. The pattern sources
  // are compile-time constants, so the fallback rule is unreachable.
  let image_rule = @provider.SupportedUrlRule::new("image/*", ["^ms://.*$"]) catch {
    _ => @provider.SupportedUrlRule::all("image/*")
  }
  let video_rule = @provider.SupportedUrlRule::new("video/*", ["^ms://.*$"]) catch {
    _ => @provider.SupportedUrlRule::all("video/*")
  }
  [image_rule, video_rule]
}

///|
impl @provider.LanguageModelV4 for MoonshotAIChatLanguageModel with fn do_generate(
  self,
  options,
) {
  let prepared = prepare_moonshot_v4_request(
    self.model_id,
    options,
    self.provider_name,
    false,
    self.include_usage,
    self.supports_structured_outputs,
  )
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.chat_url(),
    headers=self.request_headers(options.headers),
    body=prepared.body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=moonshot_error_message,
    transport=self.http_transport,
  )
  let decoded = @provider_utils.handle_json_response(response, value => {
    decode_moonshot_chat_response(
      value,
      provider_name=self.provider_name,
      id_generator=self.id_generator,
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
impl @provider.LanguageModelV4 for MoonshotAIChatLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  let prepared = prepare_moonshot_v4_request(
    self.model_id,
    options,
    self.provider_name,
    true,
    self.include_usage,
    self.supports_structured_outputs,
  )
  let decoder = MoonshotStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
    provider_name=self.provider_name,
    id_generator=self.id_generator,
  )
  let warnings = prepared.warnings
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.provider_name,
    url=self.chat_url(),
    headers=self.request_headers(options.headers),
    body=prepared.body,
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
    error_to_message=moonshot_error_message,
    start_events=[
      @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
    ],
    is_stream_error=event => event is @provider.V4Error(_),
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    finish_stream=() => decoder.finish_stream(),
    response=() => decoder.response_metadata_snapshot(),
    transport=self.http_transport,
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
