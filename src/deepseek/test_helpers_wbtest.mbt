///|
/// Adapt older normalized prompt fixtures to the V4 request core without
/// retaining a second production request encoder.
fn deepseek_test_v4_options_from_chat(
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
fn prepare_deepseek_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  provider_name : String,
  stream : Bool,
  supports_thinking : Bool,
  supports_structured_outputs : Bool,
) -> PreparedDeepSeekRequest {
  prepare_deepseek_v4_request(
    model_id,
    deepseek_test_v4_options_from_chat(options),
    provider_name,
    stream,
    supports_thinking,
    supports_structured_outputs,
  )
}

///|
fn encode_deepseek_chat_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  stream? : Bool = false,
  provider_name? : String = "deepseek.chat",
  supports_thinking? : Bool = true,
  supports_structured_outputs? : Bool = false,
) -> Json {
  prepare_deepseek_request(
    model_id, options, provider_name, stream, supports_thinking, supports_structured_outputs,
  ).body
}
