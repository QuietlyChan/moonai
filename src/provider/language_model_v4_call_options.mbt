///|
/// JSON output settings carried by the V4 language-model contract.
pub(all) struct LanguageModelV4JsonResponseFormat {
  schema : Json?
  name : String?
  description : String?
} derive(Debug)

///|
/// Standardized response format requested from a V4 language model.
pub(all) enum LanguageModelV4ResponseFormat {
  V4ResponseText
  V4ResponseJson(LanguageModelV4JsonResponseFormat)
} derive(Debug)

///|
/// Request V4 JSON output, optionally constrained by a JSON Schema.
pub fn LanguageModelV4ResponseFormat::json(
  schema? : Json,
  name? : String,
  description? : String,
) -> LanguageModelV4ResponseFormat {
  V4ResponseJson({ schema, name, description })
}

///|
/// Request unconstrained V4 JSON object output.
pub fn LanguageModelV4ResponseFormat::json_object() -> LanguageModelV4ResponseFormat {
  LanguageModelV4ResponseFormat::json()
}

///|
/// Convert a legacy response format to the V4 contract.
pub fn LanguageModelV4ResponseFormat::from_response_format(
  format : ResponseFormat,
) -> LanguageModelV4ResponseFormat {
  match format {
    Text => V4ResponseText
    JsonResponse(value) =>
      V4ResponseJson({
        schema: value.schema,
        name: value.name,
        description: value.description,
      })
  }
}

///|
/// Convert a V4 response format to the normalized legacy representation.
pub fn LanguageModelV4ResponseFormat::to_response_format(
  self : LanguageModelV4ResponseFormat,
) -> ResponseFormat {
  match self {
    V4ResponseText => Text
    V4ResponseJson(value) =>
      JsonResponse({
        schema: value.schema,
        name: value.name,
        description: value.description,
      })
  }
}

///|
/// Reasoning effort requested from a V4 language model.
pub(all) enum LanguageModelV4ReasoningEffort {
  V4ReasoningProviderDefault
  V4ReasoningNone
  V4ReasoningMinimal
  V4ReasoningLow
  V4ReasoningMedium
  V4ReasoningHigh
  V4ReasoningXHigh
} derive(Debug, Eq)

///|
/// Convert normalized reasoning effort to the V4 contract.
pub fn LanguageModelV4ReasoningEffort::from_reasoning_effort(
  effort : ReasoningEffort,
) -> LanguageModelV4ReasoningEffort {
  match effort {
    ProviderDefault => V4ReasoningProviderDefault
    Disabled => V4ReasoningNone
    Minimal => V4ReasoningMinimal
    Low => V4ReasoningLow
    Medium => V4ReasoningMedium
    High => V4ReasoningHigh
    XHigh => V4ReasoningXHigh
  }
}

///|
/// Convert V4 reasoning effort to the normalized legacy representation.
pub fn LanguageModelV4ReasoningEffort::to_reasoning_effort(
  self : LanguageModelV4ReasoningEffort,
) -> ReasoningEffort {
  match self {
    V4ReasoningProviderDefault => ProviderDefault
    V4ReasoningNone => Disabled
    V4ReasoningMinimal => Minimal
    V4ReasoningLow => Low
    V4ReasoningMedium => Medium
    V4ReasoningHigh => High
    V4ReasoningXHigh => XHigh
  }
}

///|
/// Options passed to `LanguageModelV4::do_generate` and `do_stream`.
///
/// This is intentionally separate from the high-level prompt in `ai/prompt`.
/// Callers of this contract must provide a normalized V4 provider prompt.
pub(all) struct LanguageModelV4CallOptions {
  prompt : LanguageModelV4Prompt
  tools : Array[LanguageModelV4Tool]
  tool_choice : LanguageModelV4ToolChoice?
  response_format : LanguageModelV4ResponseFormat
  reasoning : LanguageModelV4ReasoningEffort
  max_output_tokens : Int?
  temperature : Double?
  top_p : Double?
  top_k : Double?
  frequency_penalty : Double?
  presence_penalty : Double?
  seed : Int?
  stop_sequences : Array[String]
  include_raw_chunks : Bool
  headers : Map[String, String]
  provider_options : Map[String, Json]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct V4 language-model call options.
pub fn LanguageModelV4CallOptions::new(
  prompt : LanguageModelV4Prompt,
  tools? : Array[LanguageModelV4Tool] = [],
  tool_choice? : LanguageModelV4ToolChoice,
  response_format? : LanguageModelV4ResponseFormat = V4ResponseText,
  reasoning? : LanguageModelV4ReasoningEffort = V4ReasoningProviderDefault,
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
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> LanguageModelV4CallOptions {
  {
    prompt,
    tools,
    tool_choice,
    response_format,
    reasoning,
    max_output_tokens,
    temperature,
    top_p,
    top_k,
    frequency_penalty,
    presence_penalty,
    seed,
    stop_sequences,
    include_raw_chunks,
    headers,
    provider_options,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Return a copy of V4 call options with provider-specific values merged.
pub fn LanguageModelV4CallOptions::with_provider_options(
  self : LanguageModelV4CallOptions,
  options : Map[String, Json],
) -> LanguageModelV4CallOptions {
  {
    prompt: self.prompt,
    tools: self.tools.copy(),
    tool_choice: self.tool_choice,
    response_format: self.response_format,
    reasoning: self.reasoning,
    max_output_tokens: self.max_output_tokens,
    temperature: self.temperature,
    top_p: self.top_p,
    top_k: self.top_k,
    frequency_penalty: self.frequency_penalty,
    presence_penalty: self.presence_penalty,
    seed: self.seed,
    stop_sequences: self.stop_sequences.copy(),
    include_raw_chunks: self.include_raw_chunks,
    headers: copy_v4_headers(self.headers),
    provider_options: merge_provider_metadata(self.provider_options, options),
    retry_policy: self.retry_policy,
    cancellation_token: self.cancellation_token,
  }
}

///|
/// Return a copy with the V4 reasoning setting replaced.
pub fn LanguageModelV4CallOptions::with_reasoning(
  self : LanguageModelV4CallOptions,
  reasoning : LanguageModelV4ReasoningEffort,
) -> LanguageModelV4CallOptions {
  {
    prompt: self.prompt,
    tools: self.tools.copy(),
    tool_choice: self.tool_choice,
    response_format: self.response_format,
    reasoning,
    max_output_tokens: self.max_output_tokens,
    temperature: self.temperature,
    top_p: self.top_p,
    top_k: self.top_k,
    frequency_penalty: self.frequency_penalty,
    presence_penalty: self.presence_penalty,
    seed: self.seed,
    stop_sequences: self.stop_sequences.copy(),
    include_raw_chunks: self.include_raw_chunks,
    headers: copy_v4_headers(self.headers),
    provider_options: merge_provider_metadata(self.provider_options, Map([])),
    retry_policy: self.retry_policy,
    cancellation_token: self.cancellation_token,
  }
}

///|
fn copy_v4_headers(headers : Map[String, String]) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in headers.iter2() {
    result[entry.0] = entry.1
  }
  result
}

///|
/// Construct V4 call options from the normalized prompt used by legacy
/// adapters. New provider-facing code should call `new` with V4 values.
pub fn LanguageModelV4CallOptions::from_language_model_prompt(
  prompt : LanguageModelPrompt,
  tools? : Array[ToolDefinition] = [],
  tool_choice? : ToolChoice,
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
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> LanguageModelV4CallOptions {
  LanguageModelV4CallOptions::new(
    LanguageModelV4Prompt::from_language_model_prompt(prompt),
    tools=LanguageModelV4Tool::from_tool_definitions(tools),
    tool_choice?=match tool_choice {
      Some(value) => Some(LanguageModelV4ToolChoice::from_tool_choice(value))
      None => None
    },
    response_format=LanguageModelV4ResponseFormat::from_response_format(
      response_format,
    ),
    reasoning=LanguageModelV4ReasoningEffort::from_reasoning_effort(
      reasoning_effort,
    ),
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
    retry_policy~,
    cancellation_token?,
  )
}

///|
/// Convert the versioned contract to the existing provider call contract at
/// an explicit legacy or third-party adapter boundary.
pub fn LanguageModelV4CallOptions::to_chat_call_options(
  self : LanguageModelV4CallOptions,
) -> ChatCallOptions {
  ChatCallOptions::new(
    self.prompt.to_language_model_prompt(),
    tools=LanguageModelV4Tool::to_tool_definitions(self.tools),
    tool_choice?=match self.tool_choice {
      Some(value) => Some(value.to_tool_choice())
      None => None
    },
    response_format=self.response_format.to_response_format(),
    reasoning_effort=self.reasoning.to_reasoning_effort(),
    max_output_tokens?=self.max_output_tokens,
    temperature?=self.temperature,
    top_p?=self.top_p,
    top_k?=self.top_k,
    frequency_penalty?=self.frequency_penalty,
    presence_penalty?=self.presence_penalty,
    seed?=self.seed,
    stop_sequences=self.stop_sequences,
    include_raw_chunks=self.include_raw_chunks,
    headers=self.headers,
    provider_options=self.provider_options,
    retry_policy=self.retry_policy,
    cancellation_token?=self.cancellation_token,
  )
}
