///|
/// Provider-specific normalization hook for a native V4 call.
pub type OpenAICompatibleV4OptionsTransformer = (
  @provider.LanguageModelV4CallOptions,
) -> @provider.LanguageModelV4CallOptions

///|
fn identity_compatible_v4_options(
  options : @provider.LanguageModelV4CallOptions,
) -> @provider.LanguageModelV4CallOptions {
  options
}

///|
/// Configuration for one OpenAI-compatible Chat Completions model.
///
/// This is the MoonBit equivalent of AI SDK's
/// `OpenAICompatibleChatConfig`: the public language-model class owns this
/// configuration directly instead of wrapping a legacy wire model.
pub struct OpenAICompatibleChatConfig {
  priv provider_name : String
  priv api_key : String
  priv api_key_environment_variable : String?
  priv base_url : String
  priv headers : Map[String, String]
  priv query_params : Map[String, String]
  priv include_usage : Bool
  priv supports_structured_outputs : Bool
  priv supports_top_k : Bool
  priv supports_frequency_penalty : Bool
  priv supported_url_rules : Array[@provider.SupportedUrlRule]
  priv transform_request_body : (Json) -> Json
  priv error_structure : OpenAICompatibleErrorStructure
  priv metadata_extractor : OpenAICompatibleMetadataExtractor?
  priv convert_usage : OpenAICompatibleUsageConverter
  priv validate_response : OpenAICompatibleJsonValidator
  priv validate_stream_chunk : OpenAICompatibleJsonValidator
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv generate_reasoning_ids : Bool
  priv text_stream_id : String
  priv close_text_before_reasoning : Bool
  priv close_text_before_tool_calls : Bool
  priv http_transport : &@provider_utils.HttpTransport
  priv prompt_converter : OpenAICompatibleV4PromptConverter
  priv transform_options : OpenAICompatibleV4OptionsTransformer
}

///|
/// Construct Chat Completions model configuration.
pub fn OpenAICompatibleChatConfig::new(
  provider_name~ : String,
  base_url~ : String,
  api_key? : String = "",
  api_key_environment_variable? : String,
  headers? : Map[String, String] = Map([]),
  query_params? : Map[String, String] = Map([]),
  include_usage? : Bool = false,
  supports_structured_outputs? : Bool = false,
  supports_top_k? : Bool = false,
  supports_frequency_penalty? : Bool = true,
  supported_urls? : Array[@provider.SupportedUrlRule] = [],
  transform_request_body? : (Json) -> Json = value => value,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  metadata_extractor? : OpenAICompatibleMetadataExtractor,
  convert_usage? : OpenAICompatibleUsageConverter = convert_openai_compatible_chat_usage,
  validate_response? : OpenAICompatibleJsonValidator = validate_openai_compatible_chat_response,
  validate_stream_chunk? : OpenAICompatibleJsonValidator = validate_openai_compatible_chat_chunk,
  idle_timeout_ms? : Int = 120_000,
  id_generator? : @provider_utils.IdGenerator,
  generate_reasoning_ids? : Bool = false,
  text_stream_id? : String = "txt-0",
  close_text_before_reasoning? : Bool = false,
  close_text_before_tool_calls? : Bool = false,
  http_transport? : &@provider_utils.HttpTransport,
  prompt_converter? : OpenAICompatibleV4PromptConverter = default_openai_compatible_v4_prompt_converter,
  transform_options? : OpenAICompatibleV4OptionsTransformer = identity_compatible_v4_options,
) -> OpenAICompatibleChatConfig {
  {
    provider_name,
    api_key,
    api_key_environment_variable,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    query_params: @provider_utils.copy_headers(query_params),
    include_usage,
    supports_structured_outputs,
    supports_top_k,
    supports_frequency_penalty,
    supported_url_rules: supported_urls.copy(),
    transform_request_body,
    error_structure,
    metadata_extractor,
    convert_usage,
    validate_response,
    validate_stream_chunk,
    idle_timeout_ms,
    id_generator: id_generator.unwrap_or(@provider_utils.generate_id),
    generate_reasoning_ids,
    text_stream_id,
    close_text_before_reasoning,
    close_text_before_tool_calls,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
    prompt_converter,
    transform_options,
  }
}

///|
/// OpenAI-compatible Chat Completions implementation of `LanguageModelV4`.
pub struct OpenAICompatibleChatLanguageModel {
  priv model_id_value : OpenAICompatibleChatModelId
  priv config : OpenAICompatibleChatConfig
}

///|
/// Construct an OpenAI-compatible Chat Completions language model.
pub fn OpenAICompatibleChatLanguageModel::new(
  model_id : OpenAICompatibleChatModelId,
  config : OpenAICompatibleChatConfig,
) -> OpenAICompatibleChatLanguageModel {
  { model_id_value: model_id, config }
}

///|
fn OpenAICompatibleChatLanguageModel::chat_completions_url(
  self : OpenAICompatibleChatLanguageModel,
) -> String {
  @provider_utils.append_query(
    @provider_utils.append_path(self.config.base_url, "/chat/completions"),
    self.config.query_params,
  )
}

///|
fn OpenAICompatibleChatLanguageModel::request_headers_with(
  self : OpenAICompatibleChatLanguageModel,
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
pub impl @provider.LanguageModelV4 for OpenAICompatibleChatLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleChatLanguageModel with fn provider(
  self,
) -> String {
  self.config.provider_name
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleChatLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id_value
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleChatLanguageModel with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.config.supported_url_rules.copy()
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleChatLanguageModel with fn do_generate(
  self,
  options,
) {
  let effective_options = (self.config.transform_options)(options)
  let prepared = prepare_compatible_v4_chat_request(
    self.model_id_value,
    effective_options,
    self.config.include_usage,
    false,
    self.config.provider_name,
    self.config.supports_structured_outputs,
    self.config.supports_top_k,
    self.config.supports_frequency_penalty,
    self.config.prompt_converter,
  )
  let request_body = (self.config.transform_request_body)(prepared.body)
  let response = @provider_utils.post_json(
    provider_name=self.config.provider_name,
    url=self.chat_completions_url(),
    headers=self.request_headers_with(effective_options.headers),
    body=request_body,
    timeout_ms=self.config.idle_timeout_ms,
    retry_policy=effective_options.retry_policy,
    cancellation_token?=effective_options.cancellation_token,
    error_to_message=json => self.config.error_structure.message(json),
    is_retryable_response=(status_code, error) => {
      self.config.error_structure.retryable(status_code, error)
    },
    transport=self.config.http_transport,
  )
  let decoded = @provider_utils.handle_json_response(response, value => {
    decode_chat_response(
      value,
      self.config.error_structure,
      self.config.convert_usage,
      prepared.metadata_key,
      self.config.id_generator,
      self.config.validate_response,
    )
  })
  let provider_metadata = @provider.merge_provider_metadata(
    @provider.merge_provider_metadata(
      @provider_utils.provider_metadata_from_json(
        response.value,
        self.config.provider_name,
      ),
      match self.config.metadata_extractor {
        Some(extractor) => extractor.extract_metadata(response.value)
        None => Map([])
      },
    ),
    decoded.provider_metadata,
  )
  {
    content: decoded.content,
    finish_reason: decoded.finish_reason,
    usage: decoded.usage,
    provider_metadata,
    request: Some(response.request),
    response: Some(
      @provider.merge_response_metadata(decoded.response, response.response),
    ),
    warnings: prepared.warnings,
  }
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleChatLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  let effective_options = (self.config.transform_options)(options)
  let prepared = prepare_compatible_v4_chat_request(
    self.model_id_value,
    effective_options,
    self.config.include_usage,
    true,
    self.config.provider_name,
    self.config.supports_structured_outputs,
    self.config.supports_top_k,
    self.config.supports_frequency_penalty,
    self.config.prompt_converter,
  )
  let decoder = OpenAICompatibleStreamDecoder::new(
    effective_options.include_raw_chunks,
    self.config.provider_name,
    prepared.metadata_key,
    self.config.error_structure,
    self.config.metadata_extractor,
    self.config.convert_usage,
    self.config.id_generator,
    self.config.generate_reasoning_ids,
    self.config.text_stream_id,
    self.config.close_text_before_reasoning,
    self.config.close_text_before_tool_calls,
    self.config.validate_stream_chunk,
  )
  let warnings = prepared.warnings
  let request_body = (self.config.transform_request_body)(prepared.body)
  let result = @provider_utils.post_json_sse_events(
    provider_name=self.config.provider_name,
    url=self.chat_completions_url(),
    headers=self.request_headers_with(effective_options.headers),
    body=request_body,
    idle_timeout_ms=self.config.idle_timeout_ms,
    expected_terminator="[DONE]",
    retry_policy=effective_options.retry_policy,
    cancellation_token?=effective_options.cancellation_token,
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
