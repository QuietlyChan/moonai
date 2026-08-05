///|
/// LanguageModelMessageRole of one normalized provider-facing language-model message.
pub(all) enum LanguageModelMessageRole {
  System
  User
  Assistant
  Tool(String)
} derive(Debug, Eq)

///|
/// Provider-specific identifiers for one logical uploaded file.
///
/// A single reference can retain identifiers from multiple providers, for
/// example `openai -> file-abc` and `anthropic -> file-xyz`.
pub(all) struct ProviderReference {
  entries : Map[String, String]
} derive(Debug, Eq)

///|
/// Construct a provider reference from provider-to-file-id entries.
pub fn ProviderReference::new(
  entries : Map[String, String],
) -> ProviderReference {
  let copied : Map[String, String] = Map([])
  for entry in entries.iter2() {
    let (provider, id) = entry
    copied[provider] = id
  }
  { entries: copied }
}

///|
/// Construct a reference containing one provider identifier.
pub fn ProviderReference::single(
  provider~ : String,
  id~ : String,
) -> ProviderReference {
  ProviderReference::new(Map([(provider, id)]))
}

///|
/// Look up a provider-specific identifier.
pub fn ProviderReference::get(
  self : ProviderReference,
  provider : String,
) -> String? {
  self.entries.get(provider)
}

///|
/// Return the provider names available on this reference.
pub fn ProviderReference::providers(self : ProviderReference) -> Array[String] {
  [
    for entry in self.entries.iter2() => entry.0
  ]
}

///|
/// Convert a role to the OpenAI wire name.
pub fn LanguageModelMessageRole::to_openai_string(
  self : LanguageModelMessageRole,
) -> String {
  match self {
    System => "system"
    User => "user"
    Assistant => "assistant"
    Tool(_) => "tool"
  }
}

///|
/// A normalized content part consumed by provider language models.
pub(all) enum LanguageModelContentPart {
  Text(String)
  ImageUrl(String)
  ImageData(data~ : String, media_type~ : String)
  AudioData(data~ : String, format~ : String)
  FileUrl(url~ : String, media_type~ : String, filename~ : String)
  FileData(data~ : String, media_type~ : String, filename~ : String)
  FileReference(
    reference~ : ProviderReference,
    media_type~ : String,
    filename~ : String
  )
  Reasoning(String)
  ReasoningFileUrl(url~ : String, media_type~ : String)
  ReasoningFileData(data~ : String, media_type~ : String)
  Custom(kind~ : String)
  ToolCallPart(ToolCall)
  ToolResultPart(LanguageModelToolResult)
  ToolApprovalRequestPart(LanguageModelToolApprovalRequest)
  ToolApprovalResponsePart(LanguageModelToolApprovalResponse)
  /// Provider-specific options attached to one prompt content part.
  ///
  /// The wrapper matches AI SDK's per-part `providerOptions` field.
  /// Nested wrappers are normalized by `with_provider_options`.
  ProviderOptions(
    part~ : LanguageModelContentPart,
    options~ : Map[String, Json]
  )
} derive(Debug, Eq)

///|
/// Construct a text content part.
pub fn LanguageModelContentPart::text(
  value : String,
) -> LanguageModelContentPart {
  Text(value)
}

///|
/// Construct an image URL content part.
pub fn LanguageModelContentPart::image_url(
  value : String,
) -> LanguageModelContentPart {
  ImageUrl(value)
}

///|
/// Construct a base64 image content part.
pub fn LanguageModelContentPart::image_data(
  data~ : String,
  media_type~ : String,
) -> LanguageModelContentPart {
  ImageData(data~, media_type~)
}

///|
/// Construct a base64 audio content part.
pub fn LanguageModelContentPart::audio_data(
  data~ : String,
  format~ : String,
) -> LanguageModelContentPart {
  AudioData(data~, format~)
}

///|
/// Construct a URL-backed file content part.
pub fn LanguageModelContentPart::file_url(
  url~ : String,
  media_type? : String = "application/octet-stream",
  filename? : String = "",
) -> LanguageModelContentPart {
  FileUrl(url~, media_type~, filename~)
}

///|
/// Construct a base64 file content part.
pub fn LanguageModelContentPart::file_data(
  data~ : String,
  media_type~ : String,
  filename~ : String,
) -> LanguageModelContentPart {
  FileData(data~, media_type~, filename~)
}

///|
/// Construct a provider-reference-backed file content part.
pub fn LanguageModelContentPart::file_reference(
  reference~ : ProviderReference,
  media_type? : String = "application/octet-stream",
  filename? : String = "",
) -> LanguageModelContentPart {
  FileReference(reference~, media_type~, filename~)
}

///|
/// Construct a reasoning text content part.
pub fn LanguageModelContentPart::reasoning(
  value : String,
) -> LanguageModelContentPart {
  Reasoning(value)
}

///|
/// Construct a URL-backed reasoning file content part.
pub fn LanguageModelContentPart::reasoning_file_url(
  url~ : String,
  media_type~ : String,
) -> LanguageModelContentPart {
  ReasoningFileUrl(url~, media_type~)
}

///|
/// Construct a base64 reasoning file content part.
pub fn LanguageModelContentPart::reasoning_file_data(
  data~ : String,
  media_type~ : String,
) -> LanguageModelContentPart {
  ReasoningFileData(data~, media_type~)
}

///|
/// Construct a provider-specific custom content part.
pub fn LanguageModelContentPart::custom(
  kind : String,
) -> LanguageModelContentPart {
  Custom(kind~)
}

///|
/// Construct a tool-call content part.
pub fn LanguageModelContentPart::tool_call(
  call : ToolCall,
) -> LanguageModelContentPart {
  ToolCallPart(call)
}

///|
/// Construct a tool-result content part.
pub fn LanguageModelContentPart::tool_result(
  result : LanguageModelToolResult,
) -> LanguageModelContentPart {
  ToolResultPart(result)
}

///|
/// Construct a tool-approval request content part.
pub fn LanguageModelContentPart::tool_approval_request(
  request : LanguageModelToolApprovalRequest,
) -> LanguageModelContentPart {
  ToolApprovalRequestPart(request)
}

///|
/// Construct a tool-approval response content part.
pub fn LanguageModelContentPart::tool_approval_response(
  response : LanguageModelToolApprovalResponse,
) -> LanguageModelContentPart {
  ToolApprovalResponsePart(response)
}

///|
/// Attach provider-specific options to a prompt content part.
///
/// `options` uses the same provider-keyed shape as `ChatCallOptions`:
/// `{ "anthropic": { ... } }`. Empty options leave the original part intact.
pub fn LanguageModelContentPart::with_provider_options(
  self : LanguageModelContentPart,
  options : Map[String, Json],
) -> LanguageModelContentPart {
  guard options.length() > 0 else { return self }
  match self {
    ProviderOptions(part~, options=existing) =>
      ProviderOptions(
        part=part.without_provider_options(),
        options=merge_content_provider_options(existing, options),
      )
    _ => ProviderOptions(part=self, options~)
  }
}

///|
/// Return the provider-specific options attached to a content part.
pub fn LanguageModelContentPart::provider_options(
  self : LanguageModelContentPart,
) -> Map[String, Json] {
  match self {
    ProviderOptions(part=_, options~) => copy_content_provider_options(options)
    _ => Map([])
  }
}

///|
/// Remove the provider-options wrapper and return the wire-neutral payload.
/// Provider adapters can inspect `provider_options()` first, then pattern
/// match the result of this method without duplicating wrapper cases.
pub fn LanguageModelContentPart::without_provider_options(
  self : LanguageModelContentPart,
) -> LanguageModelContentPart {
  match self {
    ProviderOptions(part~, ..) => part.without_provider_options()
    _ => self
  }
}

///|
fn copy_content_provider_options(
  options : Map[String, Json],
) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for entry in options.iter2() {
    result[entry.0] = entry.1
  }
  result
}

///|
fn merge_content_provider_options(
  base : Map[String, Json],
  extra : Map[String, Json],
) -> Map[String, Json] {
  let result = copy_content_provider_options(base)
  for entry in extra.iter2() {
    result[entry.0] = entry.1
  }
  result
}

///|
/// A normalized provider-facing language-model message.
///
/// High-level APIs accept `ModelMessage` from `provider_utils`; only the
/// `ai/prompt` conversion layer constructs this type for provider calls.
pub(all) struct LanguageModelMessage {
  role : LanguageModelMessageRole
  content : String
  parts : Array[LanguageModelContentPart]
  tool_calls : Array[ToolCall]
  reasoning_content : String?
  provider_options : Map[String, Json]
} derive(Debug, Eq)

///|
/// A provider-facing prompt made up of normalized language-model messages.
pub type LanguageModelPrompt = Array[LanguageModelMessage]

///|
/// Construct a message with optional tool and reasoning data.
pub fn LanguageModelMessage::new(
  role : LanguageModelMessageRole,
  content~ : String,
  parts? : Array[LanguageModelContentPart] = [],
  tool_calls? : Array[ToolCall] = [],
  reasoning_content? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelMessage {
  { role, content, parts, tool_calls, reasoning_content, provider_options }
}

///|
/// Construct a system message.
pub fn LanguageModelMessage::system(
  content : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelMessage {
  LanguageModelMessage::new(System, content~, provider_options~)
}

///|
/// Construct a user message.
pub fn LanguageModelMessage::user(
  content : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelMessage {
  LanguageModelMessage::new(User, content~, provider_options~)
}

///|
/// Construct a user message from multimodal content parts.
pub fn LanguageModelMessage::user_parts(
  parts : Array[LanguageModelContentPart],
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelMessage {
  LanguageModelMessage::new(User, content="", parts~, provider_options~)
}

///|
/// Construct an assistant message.
pub fn LanguageModelMessage::assistant(
  content : String,
  tool_calls? : Array[ToolCall] = [],
  reasoning_content? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelMessage {
  LanguageModelMessage::new(
    Assistant,
    content~,
    tool_calls~,
    reasoning_content?,
    provider_options~,
  )
}

///|
/// Construct an assistant message from multimodal content parts.
pub fn LanguageModelMessage::assistant_parts(
  parts : Array[LanguageModelContentPart],
  tool_calls? : Array[ToolCall] = [],
  reasoning_content? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelMessage {
  LanguageModelMessage::new(
    Assistant,
    content="",
    parts~,
    tool_calls~,
    reasoning_content?,
    provider_options~,
  )
}

///|
/// Construct a tool-result message.
pub fn LanguageModelMessage::tool(
  tool_call_id : String,
  content : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelMessage {
  LanguageModelMessage::new(Tool(tool_call_id), content~, provider_options~)
}

///|
/// Construct a tool-result message with multimodal output content.
pub fn LanguageModelMessage::tool_parts(
  tool_call_id : String,
  parts : Array[LanguageModelContentPart],
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelMessage {
  LanguageModelMessage::new(
    Tool(tool_call_id),
    content="",
    parts~,
    provider_options~,
  )
}

///|
/// Construct a tool message containing multiple structured result or approval
/// parts without forcing a synthetic shared call id.
pub fn LanguageModelMessage::tool_content(
  parts : Array[LanguageModelContentPart],
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelMessage {
  LanguageModelMessage::new(Tool(""), content="", parts~, provider_options~)
}

///|
/// Return the tool calls represented by this assistant message.
///
/// The normalized contract accepts both the legacy `tool_calls` field and
/// `ToolCallPart` content parts.  Keep the field order for callers that use
/// the former shape, then append calls found in parts.  A call already present
/// in the field is not appended a second time when the two representations are
/// used together.
pub fn LanguageModelMessage::effective_tool_calls(
  self : LanguageModelMessage,
) -> Array[ToolCall] {
  let result = self.tool_calls.copy()
  for part in self.parts {
    match part.without_provider_options() {
      ToolCallPart(call) => {
        let mut already_present = false
        for existing in result {
          if existing.id == call.id && call.id != "" {
            already_present = true
            break
          }
        }
        if !already_present {
          result.push(call)
        }
      }
      _ => ()
    }
  }
  result
}

///|
/// Add or merge provider-specific options on a message.
pub fn LanguageModelMessage::with_provider_options(
  self : LanguageModelMessage,
  options : Map[String, Json],
) -> LanguageModelMessage {
  {
    role: self.role,
    content: self.content,
    parts: self.parts.copy(),
    tool_calls: self.tool_calls.copy(),
    reasoning_content: self.reasoning_content,
    provider_options: merge_provider_metadata(self.provider_options, options),
  }
}

///|
/// Standard token accounting returned by providers.
pub(all) struct Usage {
  input_tokens : Int
  output_tokens : Int
  total_tokens : Int
  reasoning_tokens : Int
  cached_input_tokens : Int
  cache_write_input_tokens : Int
} derive(Debug, Eq)

///|
/// Construct token usage with explicit counters.
pub fn Usage::new(
  input_tokens~ : Int,
  output_tokens~ : Int,
  total_tokens? : Int,
  reasoning_tokens? : Int = 0,
  cached_input_tokens? : Int = 0,
  cache_write_input_tokens? : Int = 0,
) -> Usage {
  {
    input_tokens,
    output_tokens,
    total_tokens: total_tokens.unwrap_or(input_tokens + output_tokens),
    reasoning_tokens,
    cached_input_tokens,
    cache_write_input_tokens,
  }
}

///|
/// Return zero token usage.
pub fn Usage::zero() -> Usage {
  {
    input_tokens: 0,
    output_tokens: 0,
    total_tokens: 0,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  }
}

///|
/// Add token accounting from two provider calls.
pub fn Usage::add(self : Usage, other : Usage) -> Usage {
  {
    input_tokens: self.input_tokens + other.input_tokens,
    output_tokens: self.output_tokens + other.output_tokens,
    total_tokens: self.total_tokens + other.total_tokens,
    reasoning_tokens: self.reasoning_tokens + other.reasoning_tokens,
    cached_input_tokens: self.cached_input_tokens + other.cached_input_tokens,
    cache_write_input_tokens: self.cache_write_input_tokens +
    other.cache_write_input_tokens,
  }
}

///|
/// Why the model stopped generating.
pub(all) enum FinishReason {
  Stop
  Length
  ToolCalls
  ContentFilter
  Error
  Unknown(String)
} derive(Debug, Eq)

///|
/// Normalize an OpenAI finish reason.
pub fn FinishReason::from_openai(value : String) -> FinishReason {
  match value {
    "stop" => Stop
    "length" => Length
    "function_call" => ToolCalls
    "tool_calls" => ToolCalls
    "content_filter" => ContentFilter
    "error" => Error
    other => Unknown(other)
  }
}

///|
/// How a provider should select from the advertised tools.
pub(all) enum ToolChoice {
  Auto
  NoTool
  Required
  Named(String)
} derive(Debug, Eq)

///|
/// JSON output settings carried by the provider-neutral language-model call.
/// Provider adapters own wire-specific strictness controls.
pub(all) struct JsonResponseFormat {
  schema : Json?
  name : String?
  description : String?
} derive(Debug)

///|
/// Standardized response format request.
pub(all) enum ResponseFormat {
  Text
  JsonResponse(JsonResponseFormat)
} derive(Debug)

///|
/// Request JSON output, optionally constrained by a JSON Schema.
pub fn ResponseFormat::json(
  schema? : Json,
  name? : String,
  description? : String,
) -> ResponseFormat {
  JsonResponse({ schema, name, description })
}

///|
/// Request unconstrained JSON object output.
pub fn ResponseFormat::json_object() -> ResponseFormat {
  ResponseFormat::json()
}

///|
/// Provider-neutral reasoning effort for models that expose reasoning controls.
pub(all) enum ReasoningEffort {
  ProviderDefault
  Disabled
  Minimal
  Low
  Medium
  High
  XHigh
} derive(Debug, Eq)

///|
/// Provider-neutral options passed to a chat model.
pub(all) struct ChatCallOptions {
  messages : LanguageModelPrompt
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
/// Construct normalized chat call options.
pub fn ChatCallOptions::new(
  messages : LanguageModelPrompt,
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
) -> ChatCallOptions {
  {
    messages,
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
/// Return a copy of these call options with provider-specific values merged.
///
/// Provider adapters use this when a normalized top-level option needs to be
/// represented in the provider namespace before the wire encoder runs. The
/// original options remain unchanged, which keeps middleware composition
/// deterministic.
pub fn ChatCallOptions::with_provider_options(
  self : ChatCallOptions,
  options : Map[String, Json],
) -> ChatCallOptions {
  {
    messages: self.messages.copy(),
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
    headers: copy_string_headers(self.headers),
    provider_options: merge_provider_metadata(self.provider_options, options),
    retry_policy: self.retry_policy,
    cancellation_token: self.cancellation_token,
  }
}

///|
/// Return a copy with the normalized reasoning setting replaced.
///
/// Provider adapters call this after consuming a top-level reasoning control so
/// the generic encoder does not emit a second, provider-incompatible field.
pub fn ChatCallOptions::with_reasoning_effort(
  self : ChatCallOptions,
  reasoning_effort : ReasoningEffort,
) -> ChatCallOptions {
  {
    messages: self.messages.copy(),
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
    headers: copy_string_headers(self.headers),
    provider_options: merge_provider_metadata(self.provider_options, Map([])),
    retry_policy: self.retry_policy,
    cancellation_token: self.cancellation_token,
  }
}

///|
fn copy_string_headers(headers : Map[String, String]) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in headers.iter2() {
    result[entry.0] = entry.1
  }
  result
}

///|
/// A fully accumulated generation response.
pub(all) struct ChatResponse {
  content : Array[GeneratedContent]
  text : String
  reasoning : String
  tool_calls : Array[ToolCall]
  usage : Usage
  finish_reason : FinishReason
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct a response without transport diagnostics.
pub fn ChatResponse::new(
  text : String,
  reasoning : String,
  tool_calls : Array[ToolCall],
  usage : Usage,
  finish_reason : FinishReason,
) -> ChatResponse {
  let content : Array[GeneratedContent] = []
  if text != "" {
    content.push(GeneratedContent::text(text))
  }
  if reasoning != "" {
    content.push(GeneratedContent::reasoning(reasoning))
  }
  for call in tool_calls {
    content.push(GeneratedContent::tool_call(call))
  }
  ChatResponse::from_content(content, usage, finish_reason)
}

///|
/// Construct a response from ordered provider output content.
pub fn ChatResponse::from_content(
  content : Array[GeneratedContent],
  usage : Usage,
  finish_reason : FinishReason,
) -> ChatResponse {
  let text = StringBuilder::new()
  let reasoning = StringBuilder::new()
  let tool_calls : Array[ToolCall] = []
  for part in content {
    match part {
      GeneratedTextOutput(value) => text.write_string(value.text)
      GeneratedReasoningOutput(value) => reasoning.write_string(value.text)
      GeneratedToolCallOutput(value) => tool_calls.push(value)
      _ => ()
    }
  }
  {
    content,
    text: text.to_string(),
    reasoning: reasoning.to_string(),
    tool_calls,
    usage,
    finish_reason,
    request: None,
    response: None,
    provider_metadata: Map([]),
    warnings: [],
  }
}

///|
/// Return an empty accumulated response.
pub fn ChatResponse::empty() -> ChatResponse {
  {
    content: [],
    text: "",
    reasoning: "",
    tool_calls: [],
    usage: Usage::zero(),
    finish_reason: Unknown(""),
    request: None,
    response: None,
    provider_metadata: Map([]),
    warnings: [],
  }
}

///|
/// Attach transport and provider diagnostics to an accumulated response.
pub fn ChatResponse::with_diagnostics(
  self : ChatResponse,
  request : RequestMetadata?,
  response : ResponseMetadata?,
  provider_metadata : Map[String, Json],
  warnings : Array[Warning],
) -> ChatResponse {
  {
    content: self.content,
    text: self.text,
    reasoning: self.reasoning,
    tool_calls: self.tool_calls,
    usage: self.usage,
    finish_reason: self.finish_reason,
    request,
    response,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Add HTTP metadata to a response while preserving decoder metadata.
pub fn ChatResponse::with_transport(
  self : ChatResponse,
  request : RequestMetadata,
  response : ResponseMetadata,
) -> ChatResponse {
  {
    content: self.content,
    text: self.text,
    reasoning: self.reasoning,
    tool_calls: self.tool_calls,
    usage: self.usage,
    finish_reason: self.finish_reason,
    request: Some(request),
    response: Some(merge_response_metadata(self.response, response)),
    provider_metadata: copy_provider_metadata(self.provider_metadata),
    warnings: copy_warnings(self.warnings),
  }
}

///|
/// The stable event protocol emitted by all streaming providers.
pub(all) enum StreamEvent {
  StreamStart
  Warning(Warning)
  TextStart(String)
  TextDelta(id~ : String, delta~ : String)
  TextEnd(String)
  ReasoningStart(String)
  ReasoningDelta(id~ : String, delta~ : String)
  ReasoningEnd(String)
  ToolInputStart(id~ : String, tool_name~ : String)
  ToolInputDelta(id~ : String, delta~ : String)
  ToolInputEnd(String)
  ToolCallReady(ToolCall)
  ToolResultReady(ToolResult)
  ToolApprovalRequestReady(ToolApprovalRequest)
  FileReady(GeneratedFile)
  ReasoningFileReady(GeneratedFile)
  SourceReady(GeneratedSource)
  CustomContentReady(GeneratedCustomContent)
  ResponseMetadataReady(ResponseMetadata)
  Finish(usage~ : Usage, reason~ : FinishReason)
  Raw(Json)
  StreamError(String)
} derive(Debug)
