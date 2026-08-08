///|
/// Keep legacy-shaped fixtures out of the production Anthropic boundary while
/// retaining coverage for the shared prompt and response normalization core.
fn anthropic_test_v4_options_from_chat(
  options : @provider.ChatCallOptions,
) -> @provider.LanguageModelV4CallOptions {
  @provider.LanguageModelV4CallOptions::from_language_model_prompt(
    options.messages,
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
fn prepare_anthropic_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  provider_name : String,
  stream : Bool,
) -> AnthropicPreparedRequest raise {
  prepare_anthropic_v4_request(
    model_id,
    anthropic_test_v4_options_from_chat(options),
    provider_name,
    stream,
  )
}

///|
fn encode_messages_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  provider_name? : String = "",
  stream? : Bool = true,
) -> Json raise {
  prepare_anthropic_request(model_id, options, provider_name, stream).body
}

///|
fn AnthropicStreamDecoder::new(
  include_raw_chunks? : Bool = false,
  provider_name? : String = "",
  mark_code_execution_dynamic? : Bool = false,
  uses_json_response_tool? : Bool = false,
  tool_name_mapping? : @provider_utils.ToolNameMapping,
  id_generator? : @provider_utils.IdGenerator,
  citation_documents? : Array[AnthropicCitationDocument] = [],
) -> AnthropicStreamDecoder {
  AnthropicStreamDecoder::new_with_metadata_policy(
    include_raw_chunks~,
    provider_name~,
    canonical_metadata=false,
    include_custom_provider_metadata=false,
    mark_code_execution_dynamic~,
    uses_json_response_tool~,
    tool_name_mapping=tool_name_mapping.unwrap_or(
      @provider_utils.ToolNameMapping::identity(),
    ),
    id_generator=id_generator.unwrap_or(@provider_utils.generate_id),
    citation_documents~,
  )
}

///|
fn decode_messages_response(
  json : Json,
  provider_name? : String = "anthropic.messages",
  mark_code_execution_dynamic? : Bool = false,
  uses_json_response_tool? : Bool = false,
  tool_name_mapping? : @provider_utils.ToolNameMapping,
  id_generator? : @provider_utils.IdGenerator,
  citation_documents? : Array[AnthropicCitationDocument] = [],
) -> @provider.ChatResponse raise {
  let decoded = decode_messages_response_with_metadata(
    json,
    provider_name~,
    canonical_metadata=false,
    include_custom_provider_metadata=false,
    mark_code_execution_dynamic~,
    uses_json_response_tool~,
    tool_name_mapping=tool_name_mapping.unwrap_or(
      @provider_utils.ToolNameMapping::identity(),
    ),
    id_generator=id_generator.unwrap_or(@provider_utils.generate_id),
    citation_documents~,
  )
  @provider.ChatResponse::from_content(
    @provider.LanguageModelV4Content::to_generated_content_array(
      decoded.content,
    ),
    decoded.usage.to_usage(),
    match decoded.finish_reason {
      { unified: @provider.V4FinishOther, raw: None } => @provider.Unknown("")
      reason => reason.to_finish_reason()
    },
  ).with_diagnostics(None, decoded.response, decoded.provider_metadata, [])
}
