///|
/// Generate text through the provider-neutral AI SDK language-model contract.
///
/// Prompt normalization, validation, asset downloads, retries, and
/// cancellation are owned by this layer. Provider packages only implement
/// `LanguageModelV4::do_generate`.
pub async fn generate_text(
  model : &@provider.LanguageModelV4,
  prompt? : String,
  messages? : Array[ModelMessage] = [],
  instructions? : Instructions,
  allow_system_in_messages? : Bool = false,
  tools? : Array[ToolDefinition] = [],
  tool_choice? : ToolChoice = Auto,
  response_format? : ResponseFormat = Text,
  reasoning_effort? : ReasoningEffort = ProviderDefault,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  top_k? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  include_raw_chunks? : Bool = false,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  experimental_download? : DownloadFunction,
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> @provider.LanguageModelV4GenerateResult {
  @provider.check_cancellation(cancellation_token)
  model.do_generate(
    @prompt.prepare_language_model_v4_call_options(
      model, prompt, messages, instructions, allow_system_in_messages, tools, tool_choice,
      response_format, reasoning_effort, max_output_tokens, temperature, top_p, top_k,
      frequency_penalty, presence_penalty, seed, stop_sequences, include_raw_chunks,
      headers, provider_options, experimental_download, retry_policy, cancellation_token,
    ),
  )
}

///|
/// AI SDK-style camel-case spelling for `generate_text`.
pub async fn generateText(
  model : &@provider.LanguageModelV4,
  prompt? : String,
  messages? : Array[ModelMessage] = [],
  instructions? : Instructions,
  allow_system_in_messages? : Bool = false,
  tools? : Array[ToolDefinition] = [],
  tool_choice? : ToolChoice = Auto,
  response_format? : ResponseFormat = Text,
  reasoning_effort? : ReasoningEffort = ProviderDefault,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  top_k? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  include_raw_chunks? : Bool = false,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  experimental_download? : DownloadFunction,
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> @provider.LanguageModelV4GenerateResult {
  generate_text(
    model,
    prompt?,
    messages~,
    instructions?,
    allow_system_in_messages~,
    tools~,
    tool_choice~,
    response_format~,
    reasoning_effort~,
    max_output_tokens?,
    temperature?,
    top_p?,
    top_k?,
    frequency_penalty?,
    presence_penalty?,
    seed?,
    stop_sequences~,
    include_raw_chunks~,
    headers~,
    provider_options~,
    experimental_download?,
    retry_policy~,
    cancellation_token?,
  )
}

///|
/// Stream text through the provider-neutral AI SDK language-model contract.
///
/// MoonBit represents the SDK stream as an async callback. The callback
/// receives normalized V4 stream parts and the returned value carries the
/// final usage, finish reason, and transport metadata.
pub async fn stream_text(
  model : &@provider.LanguageModelV4,
  prompt? : String,
  messages? : Array[ModelMessage] = [],
  instructions? : Instructions,
  allow_system_in_messages? : Bool = false,
  tools? : Array[ToolDefinition] = [],
  tool_choice? : ToolChoice = Auto,
  response_format? : ResponseFormat = Text,
  reasoning_effort? : ReasoningEffort = ProviderDefault,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  top_k? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  include_raw_chunks? : Bool = false,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  experimental_download? : DownloadFunction,
  on_event? : async (@provider.LanguageModelV4StreamPart) -> Unit = _ => (),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> @provider.LanguageModelV4StreamResult {
  @provider.check_cancellation(cancellation_token)
  model.do_stream(
    @prompt.prepare_language_model_v4_call_options(
      model, prompt, messages, instructions, allow_system_in_messages, tools, tool_choice,
      response_format, reasoning_effort, max_output_tokens, temperature, top_p, top_k,
      frequency_penalty, presence_penalty, seed, stop_sequences, include_raw_chunks,
      headers, provider_options, experimental_download, retry_policy, cancellation_token,
    ),
    on_event,
  )
}

///|
/// AI SDK-style camel-case spelling for `stream_text`.
pub async fn streamText(
  model : &@provider.LanguageModelV4,
  prompt? : String,
  messages? : Array[ModelMessage] = [],
  instructions? : Instructions,
  allow_system_in_messages? : Bool = false,
  tools? : Array[ToolDefinition] = [],
  tool_choice? : ToolChoice = Auto,
  response_format? : ResponseFormat = Text,
  reasoning_effort? : ReasoningEffort = ProviderDefault,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  top_k? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  include_raw_chunks? : Bool = false,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  experimental_download? : DownloadFunction,
  on_event? : async (@provider.LanguageModelV4StreamPart) -> Unit = _ => (),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> @provider.LanguageModelV4StreamResult {
  stream_text(
    model,
    prompt?,
    messages~,
    instructions?,
    allow_system_in_messages~,
    tools~,
    tool_choice~,
    response_format~,
    reasoning_effort~,
    max_output_tokens?,
    temperature?,
    top_p?,
    top_k?,
    frequency_penalty?,
    presence_penalty?,
    seed?,
    stop_sequences~,
    include_raw_chunks~,
    headers~,
    provider_options~,
    experimental_download?,
    on_event~,
    retry_policy~,
    cancellation_token?,
  )
}
