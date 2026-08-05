///|

///|
/// Versioned names for the provider-neutral V4 content values.
///
/// Generated content already has the same ordered-content semantics as the
/// V4 result contract. It remains a named alias until the provider metadata
/// map is moved from `Map[String, Json]` to a dedicated provider-keyed type.
pub type LanguageModelV4Content = GeneratedContent

///|

///|

///|
/// V4 spelling for response and transport metadata.
pub type LanguageModelV4ResponseMetadata = ResponseMetadata

///|
/// V4 spelling for provider adaptation warnings.
pub type LanguageModelV4Warning = Warning

///|
/// Options passed to `LanguageModelV4::do_generate` and `do_stream`.
///
/// This is intentionally separate from the high-level `Prompt` in
/// `ai/prompt`: callers of this contract must provide a normalized provider
/// prompt. `ChatCallOptions` is the normalized wire contract used inside
/// provider implementations.
pub(all) struct LanguageModelV4CallOptions {
  prompt : LanguageModelV4Prompt
  tools : Array[ToolDefinition]
  tool_choice : ToolChoice?
  response_format : ResponseFormat
  reasoning_effort : ReasoningEffort
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
  {
    prompt,
    tools,
    tool_choice,
    response_format,
    reasoning_effort,
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
///
/// This is the versioned counterpart of `ChatCallOptions::with_provider_options`
/// and is useful to provider-owned adapters that translate standardized V4
/// controls into a namespaced wire option.
pub fn LanguageModelV4CallOptions::with_provider_options(
  self : LanguageModelV4CallOptions,
  options : Map[String, Json],
) -> LanguageModelV4CallOptions {
  {
    prompt: self.prompt,
    tools: self.tools.copy(),
    tool_choice: self.tool_choice,
    response_format: self.response_format,
    reasoning_effort: self.reasoning_effort,
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
/// Return a copy with the normalized reasoning setting replaced.
pub fn LanguageModelV4CallOptions::with_reasoning_effort(
  self : LanguageModelV4CallOptions,
  reasoning_effort : ReasoningEffort,
) -> LanguageModelV4CallOptions {
  {
    prompt: self.prompt,
    tools: self.tools.copy(),
    tool_choice: self.tool_choice,
    response_format: self.response_format,
    reasoning_effort,
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
/// Construct V4 call options from the normalized prompt used by wire
/// adapters. New provider-facing code should call
/// `LanguageModelV4CallOptions::new` with a V4 prompt directly.
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
    tools~,
    tool_choice?,
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
    retry_policy~,
    cancellation_token?,
  )
}

///|
/// Convert the versioned contract to the existing provider call contract.
///
/// Provider implementations use this mapping only at an explicit wire or
/// third-party adapter boundary.
pub fn LanguageModelV4CallOptions::to_chat_call_options(
  self : LanguageModelV4CallOptions,
) -> ChatCallOptions {
  ChatCallOptions::new(
    self.prompt.to_language_model_prompt(),
    tools=self.tools,
    tool_choice?=self.tool_choice,
    response_format=self.response_format,
    reasoning_effort=self.reasoning_effort,
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

///|
/// A generated V4 language-model result.
pub(all) struct LanguageModelV4GenerateResult {
  content : Array[GeneratedContent]
  finish_reason : LanguageModelV4FinishReason
  usage : LanguageModelV4Usage
  provider_metadata : Map[String, Json]
  request : RequestMetadata?
  response : ResponseMetadata?
  warnings : Array[Warning]
} derive(Debug)

///|
/// Build a V4 result from the normalized response used by current providers.
pub fn LanguageModelV4GenerateResult::from_chat_response(
  response : ChatResponse,
) -> LanguageModelV4GenerateResult {
  {
    content: response.content.copy(),
    finish_reason: LanguageModelV4FinishReason::from_finish_reason(
      response.finish_reason,
    ),
    usage: LanguageModelV4Usage::from_usage(response.usage),
    provider_metadata: copy_provider_metadata(response.provider_metadata),
    request: response.request,
    response: response.response,
    warnings: copy_warnings(response.warnings),
  }
}

///|
/// Build a V4 result from an OpenAI-style completion wire response.
///
/// Completion endpoints are still language models at the public V4 boundary;
/// the separate response type only exists inside their protocol adapter.
pub fn LanguageModelV4GenerateResult::from_completion_response(
  response : CompletionResponse,
) -> LanguageModelV4GenerateResult {
  {
    content: if response.text == "" {
      []
    } else {
      [GeneratedContent::text(response.text)]
    },
    finish_reason: LanguageModelV4FinishReason::from_finish_reason(
      response.finish_reason,
    ),
    usage: LanguageModelV4Usage::from_usage(response.usage),
    provider_metadata: copy_provider_metadata(response.provider_metadata),
    request: response.request,
    response: response.response,
    warnings: copy_warnings(response.warnings),
  }
}

///|
/// Return the ordered text segments from a V4 result as one string.
///
/// The V4 contract keeps content parts structured so providers can expose
/// reasoning, files, sources, and tool calls without flattening them. This
/// convenience follows AI SDK's `GenerateTextResult.text` semantics while
/// preserving that structured content for callers that need it.
pub fn LanguageModelV4GenerateResult::text(
  self : LanguageModelV4GenerateResult,
) -> String {
  let text = StringBuilder::new()
  for part in self.content {
    match part {
      GeneratedTextOutput(value) => text.write_string(value.text)
      _ => ()
    }
  }
  text.to_string()
}

///|
/// Return the ordered reasoning segments from a V4 result as one string.
pub fn LanguageModelV4GenerateResult::reasoning(
  self : LanguageModelV4GenerateResult,
) -> String {
  let reasoning = StringBuilder::new()
  for part in self.content {
    match part {
      GeneratedReasoningOutput(value) => reasoning.write_string(value.text)
      _ => ()
    }
  }
  reasoning.to_string()
}

///|
/// Convert a V4 result back to the current normalized response shape.
pub fn LanguageModelV4GenerateResult::to_chat_response(
  self : LanguageModelV4GenerateResult,
) -> ChatResponse {
  ChatResponse::from_content(
    self.content,
    self.usage.to_usage(),
    self.finish_reason.to_finish_reason(),
  ).with_diagnostics(
    self.request,
    self.response,
    self.provider_metadata,
    self.warnings,
  )
}

///|
/// Replace the V4 usage and finish reason while preserving content and
/// diagnostics. Protocol packages use this after parsing provider-native
/// terminal metadata that is not represented by the wire `ChatResponse`.
pub fn LanguageModelV4GenerateResult::with_usage_and_finish_reason(
  self : LanguageModelV4GenerateResult,
  usage : LanguageModelV4Usage,
  finish_reason : LanguageModelV4FinishReason,
) -> LanguageModelV4GenerateResult {
  {
    content: self.content,
    finish_reason,
    usage,
    provider_metadata: self.provider_metadata,
    request: self.request,
    response: self.response,
    warnings: self.warnings,
  }
}

///|
/// Stream parts emitted by a V4 language model.
///
/// `StreamEvent` remains the wire-facing callback for `ChatModel`.
/// V4 uses a separate vocabulary so providers can expose the AI SDK stream
/// lifecycle without forcing the older contract to grow incompatible fields.
pub(all) enum LanguageModelV4StreamPart {
  V4StreamStart(warnings~ : Array[Warning])
  V4Warning(Warning)
  V4TextStart(id~ : String, provider_metadata~ : Map[String, Json])
  V4TextDelta(
    id~ : String,
    delta~ : String,
    provider_metadata~ : Map[String, Json]
  )
  V4TextEnd(id~ : String, provider_metadata~ : Map[String, Json])
  V4ReasoningStart(id~ : String, provider_metadata~ : Map[String, Json])
  V4ReasoningDelta(
    id~ : String,
    delta~ : String,
    provider_metadata~ : Map[String, Json]
  )
  V4ReasoningEnd(id~ : String, provider_metadata~ : Map[String, Json])
  V4ToolInputStart(
    id~ : String,
    tool_name~ : String,
    provider_executed~ : Bool,
    dynamic~ : Bool,
    title~ : String?,
    provider_metadata~ : Map[String, Json]
  )
  V4ToolInputDelta(
    id~ : String,
    delta~ : String,
    provider_metadata~ : Map[String, Json]
  )
  V4ToolInputEnd(id~ : String, provider_metadata~ : Map[String, Json])
  V4ToolCallReady(ToolCall)
  V4ToolResultReady(ToolResult)
  V4ToolApprovalRequestReady(ToolApprovalRequest)
  V4FileReady(GeneratedFile)
  V4ReasoningFileReady(GeneratedFile)
  V4SourceReady(GeneratedSource)
  V4CustomContentReady(GeneratedCustomContent)
  V4ResponseMetadataReady(ResponseMetadata)
  V4Finish(
    usage~ : LanguageModelV4Usage,
    reason~ : LanguageModelV4FinishReason,
    provider_metadata~ : Map[String, Json]
  )
  V4Raw(Json)
  V4Error(String)
} derive(Debug)

///|
/// Convert one provider wire event to the V4 stream vocabulary.
///
/// Warning is retained as a separate migration event because existing
/// transports emit it after `StreamStart`; new native V4 implementations can
/// emit `V4StreamStart(warnings=...)` directly.
pub fn LanguageModelV4StreamPart::from_stream_event(
  event : StreamEvent,
) -> LanguageModelV4StreamPart {
  match event {
    StreamStart => V4StreamStart(warnings=[])
    Warning(value) => V4Warning(value)
    TextStart(id) => V4TextStart(id~, provider_metadata=Map([]))
    TextDelta(id~, delta~) =>
      V4TextDelta(id~, delta~, provider_metadata=Map([]))
    TextEnd(id) => V4TextEnd(id~, provider_metadata=Map([]))
    ReasoningStart(id) => V4ReasoningStart(id~, provider_metadata=Map([]))
    ReasoningDelta(id~, delta~) =>
      V4ReasoningDelta(id~, delta~, provider_metadata=Map([]))
    ReasoningEnd(id) => V4ReasoningEnd(id~, provider_metadata=Map([]))
    ToolInputStart(id~, tool_name~) =>
      V4ToolInputStart(
        id~,
        tool_name~,
        provider_executed=false,
        dynamic=false,
        title=None,
        provider_metadata=Map([]),
      )
    ToolInputDelta(id~, delta~) =>
      V4ToolInputDelta(id~, delta~, provider_metadata=Map([]))
    ToolInputEnd(id) => V4ToolInputEnd(id~, provider_metadata=Map([]))
    ToolCallReady(value) => V4ToolCallReady(value)
    ToolResultReady(value) => V4ToolResultReady(value)
    ToolApprovalRequestReady(value) => V4ToolApprovalRequestReady(value)
    FileReady(value) => V4FileReady(value)
    ReasoningFileReady(value) => V4ReasoningFileReady(value)
    SourceReady(value) => V4SourceReady(value)
    CustomContentReady(value) => V4CustomContentReady(value)
    ResponseMetadataReady(value) => V4ResponseMetadataReady(value)
    Finish(usage~, reason~) =>
      V4Finish(
        usage=LanguageModelV4Usage::from_usage(usage),
        reason=LanguageModelV4FinishReason::from_finish_reason(reason),
        provider_metadata=Map([]),
      )
    Raw(value) => V4Raw(value)
    StreamError(message) => V4Error(message)
  }
}

///|
/// Metadata returned when a V4 streaming call is started and completed.
///
/// MoonBit models use an async callback rather than a JavaScript
/// `ReadableStream`; the callback receives `LanguageModelV4StreamPart` values
/// while this value carries the request/response diagnostics.
pub(all) struct LanguageModelV4StreamResult {
  request : RequestMetadata?
  response : ResponseMetadata?
  usage : LanguageModelV4Usage
  finish_reason : LanguageModelV4FinishReason
  provider_metadata : Map[String, Json]
  warnings : Array[LanguageModelV4Warning]
} derive(Debug)

///|
/// Construct a V4 stream result.
pub fn LanguageModelV4StreamResult::new(
  request : RequestMetadata?,
  response : ResponseMetadata?,
  usage? : LanguageModelV4Usage = LanguageModelV4Usage::unknown(),
  finish_reason? : LanguageModelV4FinishReason = LanguageModelV4FinishReason::unknown(),
  provider_metadata? : Map[String, Json] = Map([]),
  warnings? : Array[LanguageModelV4Warning] = [],
) -> LanguageModelV4StreamResult {
  {
    request,
    response,
    usage,
    finish_reason,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Versioned language-model contract corresponding to AI SDK's
/// `LanguageModelV4`.
///
/// The callback form of `do_stream` is the native MoonBit representation of a
/// readable stream.  It keeps back-pressure and cancellation in the async
/// boundary without introducing a runtime-specific stream type.
pub(open) trait LanguageModelV4 {
  fn specification_version(Self) -> String
  fn provider(Self) -> String
  fn model_id(Self) -> String
  fn supported_urls(Self) -> Array[SupportedUrlRule]
  async fn do_generate(Self, LanguageModelV4CallOptions) -> LanguageModelV4GenerateResult
  async fn do_stream(
    Self,
    LanguageModelV4CallOptions,
    async (LanguageModelV4StreamPart) -> Unit,
  ) -> LanguageModelV4StreamResult
}
