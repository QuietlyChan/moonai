///|
/// Model-facing generation controls prepared by the high-level AI layer.
///
/// This mirrors AI SDK's prompt-layer call settings. Provider-neutral prompt
/// content is added later when constructing `ChatCallOptions`.
pub(all) struct LanguageModelCallOptions {
  max_output_tokens : Int?
  temperature : Double?
  top_p : Double?
  top_k : Double?
  presence_penalty : Double?
  frequency_penalty : Double?
  stop_sequences : Array[String]
  seed : Int?
  reasoning_effort : @provider.ReasoningEffort
} derive(Debug)

///|
/// Construct model-facing generation controls before validation.
pub fn LanguageModelCallOptions::new(
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  top_k? : Double,
  presence_penalty? : Double,
  frequency_penalty? : Double,
  stop_sequences? : Array[String] = [],
  seed? : Int,
  reasoning_effort? : @provider.ReasoningEffort = @provider.ProviderDefault,
) -> LanguageModelCallOptions {
  {
    max_output_tokens,
    temperature,
    top_p,
    top_k,
    presence_penalty,
    frequency_penalty,
    stop_sequences,
    seed,
    reasoning_effort,
  }
}

///|
/// Validate model call settings and return an isolated normalized value.
pub fn prepare_language_model_call_options(
  options : LanguageModelCallOptions,
) -> LanguageModelCallOptions raise {
  if options.max_output_tokens is Some(value) && value < 1 {
    raise @provider.InvalidArgumentError(
      argument="max_output_tokens",
      message="max_output_tokens must be greater than or equal to 1",
    )
  }
  {
    max_output_tokens: options.max_output_tokens,
    temperature: options.temperature,
    top_p: options.top_p,
    top_k: options.top_k,
    presence_penalty: options.presence_penalty,
    frequency_penalty: options.frequency_penalty,
    stop_sequences: options.stop_sequences.copy(),
    seed: options.seed,
    reasoning_effort: options.reasoning_effort,
  }
}

///|
/// Prepare one provider-neutral chat call from high-level prompt input.
///
/// This owns input-shape validation, standard setting validation, and prompt
/// asset conversion. Provider packages remain responsible for wire encoding.
pub async fn prepare_chat_call_options(
  model : &@provider.ChatModel,
  prompt : String?,
  messages : Array[@provider_utils.ModelMessage],
  instructions : Instructions?,
  allow_system_in_messages : Bool,
  tools : Array[@provider.ToolDefinition],
  tool_choice : @provider.ToolChoice,
  response_format : @provider.ResponseFormat,
  reasoning_effort : @provider.ReasoningEffort,
  max_output_tokens : Int?,
  temperature : Double?,
  top_p : Double?,
  top_k : Double?,
  frequency_penalty : Double?,
  presence_penalty : Double?,
  seed : Int?,
  stop_sequences : Array[String],
  include_raw_chunks : Bool,
  headers : Map[String, String],
  provider_options : Map[String, Json],
  download : DownloadFunction?,
  retry_policy : @provider.RetryPolicy,
  cancellation_token : @provider.CancellationToken?,
) -> @provider.ChatCallOptions {
  let standardized = standardize_prompt(
    prompt,
    messages,
    instructions?,
    allow_system_in_messages~,
  )
  let settings = prepare_language_model_call_options(
    LanguageModelCallOptions::new(
      max_output_tokens?,
      temperature?,
      top_p?,
      top_k?,
      presence_penalty?,
      frequency_penalty?,
      stop_sequences~,
      seed?,
      reasoning_effort~,
    ),
  )
  let normalized_messages = convert_to_language_model_prompt(
    standardized, model, download, retry_policy, cancellation_token,
  )
  @provider.ChatCallOptions::new(
    normalized_messages,
    tools~,
    tool_choice?=if tools.length() == 0 { None } else { Some(tool_choice) },
    response_format~,
    reasoning_effort=settings.reasoning_effort,
    max_output_tokens?=settings.max_output_tokens,
    temperature?=settings.temperature,
    top_p?=settings.top_p,
    top_k?=settings.top_k,
    frequency_penalty?=settings.frequency_penalty,
    presence_penalty?=settings.presence_penalty,
    seed?=settings.seed,
    stop_sequences=settings.stop_sequences,
    include_raw_chunks~,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
}

///|
/// Prepare a high-level prompt for the AI SDK-aligned V4 model contract.
///
/// The prompt normalization and download rules are shared with ChatModel;
/// only the final call-options container differs.
pub async fn prepare_language_model_v4_call_options(
  model : &@provider.LanguageModelV4,
  prompt : String?,
  messages : Array[@provider_utils.ModelMessage],
  instructions : Instructions?,
  allow_system_in_messages : Bool,
  tools : Array[@provider.ToolDefinition],
  tool_choice : @provider.ToolChoice,
  response_format : @provider.ResponseFormat,
  reasoning_effort : @provider.ReasoningEffort,
  max_output_tokens : Int?,
  temperature : Double?,
  top_p : Double?,
  top_k : Double?,
  frequency_penalty : Double?,
  presence_penalty : Double?,
  seed : Int?,
  stop_sequences : Array[String],
  include_raw_chunks : Bool,
  headers : Map[String, String],
  provider_options : Map[String, Json],
  download : DownloadFunction?,
  retry_policy : @provider.RetryPolicy,
  cancellation_token : @provider.CancellationToken?,
) -> @provider.LanguageModelV4CallOptions {
  let standardized = standardize_prompt(
    prompt,
    messages,
    instructions?,
    allow_system_in_messages~,
  )
  let settings = prepare_language_model_call_options(
    LanguageModelCallOptions::new(
      max_output_tokens?,
      temperature?,
      top_p?,
      top_k?,
      presence_penalty?,
      frequency_penalty?,
      stop_sequences~,
      seed?,
      reasoning_effort~,
    ),
  )
  let normalized_messages = convert_to_language_model_prompt_with_context(
    standardized,
    PromptModelContext::from_language_model_v4(model),
    download,
    retry_policy,
    cancellation_token,
  )
  @provider.LanguageModelV4CallOptions::from_language_model_prompt(
    normalized_messages,
    tools~,
    tool_choice?=if tools.length() == 0 { None } else { Some(tool_choice) },
    response_format~,
    reasoning_effort=settings.reasoning_effort,
    max_output_tokens?=settings.max_output_tokens,
    temperature?=settings.temperature,
    top_p?=settings.top_p,
    top_k?=settings.top_k,
    frequency_penalty?=settings.frequency_penalty,
    presence_penalty?=settings.presence_penalty,
    seed?=settings.seed,
    stop_sequences=settings.stop_sequences,
    include_raw_chunks~,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
}

///|
/// AI SDK-style camel-case spelling for the V4 prompt preparation helper.
pub async fn prepareLanguageModelV4CallOptions(
  model : &@provider.LanguageModelV4,
  prompt : String?,
  messages : Array[@provider_utils.ModelMessage],
  instructions : Instructions?,
  allow_system_in_messages : Bool,
  tools : Array[@provider.ToolDefinition],
  tool_choice : @provider.ToolChoice,
  response_format : @provider.ResponseFormat,
  reasoning_effort : @provider.ReasoningEffort,
  max_output_tokens : Int?,
  temperature : Double?,
  top_p : Double?,
  top_k : Double?,
  frequency_penalty : Double?,
  presence_penalty : Double?,
  seed : Int?,
  stop_sequences : Array[String],
  include_raw_chunks : Bool,
  headers : Map[String, String],
  provider_options : Map[String, Json],
  download : DownloadFunction?,
  retry_policy : @provider.RetryPolicy,
  cancellation_token : @provider.CancellationToken?,
) -> @provider.LanguageModelV4CallOptions {
  prepare_language_model_v4_call_options(
    model, prompt, messages, instructions, allow_system_in_messages, tools, tool_choice,
    response_format, reasoning_effort, max_output_tokens, temperature, top_p, top_k,
    frequency_penalty, presence_penalty, seed, stop_sequences, include_raw_chunks,
    headers, provider_options, download, retry_policy, cancellation_token,
  )
}

///|
/// AI SDK-style camel-case spelling for `prepare_language_model_call_options`.
pub fn prepareLanguageModelCallOptions(
  options : LanguageModelCallOptions,
) -> LanguageModelCallOptions raise {
  prepare_language_model_call_options(options)
}
