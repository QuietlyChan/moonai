///|

///|

///|
/// V4 spelling for response and transport metadata.
pub type LanguageModelV4ResponseMetadata = ResponseMetadata

///|
/// A generated V4 language-model result.
pub(all) struct LanguageModelV4GenerateResult {
  content : Array[LanguageModelV4Content]
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
    content: LanguageModelV4Content::from_generated_content_array(
      response.content,
    ),
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
      [LanguageModelV4Content::text(response.text)]
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
      V4TextOutput(value) => text.write_string(value.text)
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
      V4ReasoningOutput(value) => reasoning.write_string(value.text)
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
    LanguageModelV4Content::to_generated_content_array(self.content),
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
  V4ToolCallReady(LanguageModelV4ToolCall)
  V4ToolResultReady(LanguageModelV4ToolResult)
  V4ToolApprovalRequestReady(LanguageModelV4ToolApprovalRequest)
  V4FileReady(LanguageModelV4File)
  V4ReasoningFileReady(LanguageModelV4ReasoningFile)
  V4SourceReady(LanguageModelV4Source)
  V4CustomContentReady(LanguageModelV4CustomContent)
  V4ResponseMetadataReady(ResponseMetadata)
  V4Finish(
    usage~ : LanguageModelV4Usage,
    reason~ : LanguageModelV4FinishReason,
    provider_metadata~ : Map[String, Json]
  )
  V4Raw(Json)
  V4Error(StreamErrorInfo)
} derive(Debug)

///|
/// Convert one provider wire event to the V4 stream vocabulary.
///
/// The legacy protocol emits warnings as standalone events. V4 carries them
/// only on `V4StreamStart`, so callers must collect legacy warnings at the
/// adapter boundary before converting the remaining events.
pub fn LanguageModelV4StreamPart::from_stream_event(
  event : StreamEvent,
) -> LanguageModelV4StreamPart? {
  match event {
    StreamStart => Some(V4StreamStart(warnings=[]))
    Warning(_) => None
    TextStart(id) => Some(V4TextStart(id~, provider_metadata=Map([])))
    TextDelta(id~, delta~) =>
      Some(V4TextDelta(id~, delta~, provider_metadata=Map([])))
    TextEnd(id) => Some(V4TextEnd(id~, provider_metadata=Map([])))
    ReasoningStart(id) => Some(V4ReasoningStart(id~, provider_metadata=Map([])))
    ReasoningDelta(id~, delta~) =>
      Some(V4ReasoningDelta(id~, delta~, provider_metadata=Map([])))
    ReasoningEnd(id) => Some(V4ReasoningEnd(id~, provider_metadata=Map([])))
    ToolInputStart(id~, tool_name~) =>
      Some(
        V4ToolInputStart(
          id~,
          tool_name~,
          provider_executed=false,
          dynamic=false,
          title=None,
          provider_metadata=Map([]),
        ),
      )
    ToolInputDelta(id~, delta~) =>
      Some(V4ToolInputDelta(id~, delta~, provider_metadata=Map([])))
    ToolInputEnd(id) => Some(V4ToolInputEnd(id~, provider_metadata=Map([])))
    ToolCallReady(value) =>
      Some(V4ToolCallReady(LanguageModelV4ToolCall::from_tool_call(value)))
    ToolResultReady(value) =>
      Some(
        V4ToolResultReady(LanguageModelV4ToolResult::from_tool_result(value)),
      )
    ToolApprovalRequestReady(value) =>
      Some(
        V4ToolApprovalRequestReady(
          LanguageModelV4ToolApprovalRequest::from_tool_approval_request(value),
        ),
      )
    FileReady(value) =>
      Some(V4FileReady(LanguageModelV4File::from_generated_file(value)))
    ReasoningFileReady(value) =>
      Some(
        V4ReasoningFileReady(
          LanguageModelV4ReasoningFile::from_generated_file(value),
        ),
      )
    SourceReady(value) =>
      Some(V4SourceReady(LanguageModelV4Source::from_generated_source(value)))
    CustomContentReady(value) =>
      Some(
        V4CustomContentReady({
          kind: value.kind,
          provider_metadata: copy_provider_metadata(value.provider_metadata),
        }),
      )
    ResponseMetadataReady(value) => Some(V4ResponseMetadataReady(value))
    Finish(usage~, reason~) =>
      Some(
        V4Finish(
          usage=LanguageModelV4Usage::from_usage(usage),
          reason=LanguageModelV4FinishReason::from_finish_reason(reason),
          provider_metadata=Map([]),
        ),
      )
    Raw(value) => Some(V4Raw(value))
    StreamError(error) => Some(V4Error(error))
  }
}

///|
/// Transport diagnostics returned by a V4 streaming call.
///
/// MoonBit models use an async callback rather than a JavaScript
/// `ReadableStream`; the callback receives `LanguageModelV4StreamPart` values
/// while this value carries the request/response diagnostics. Warnings, usage,
/// finish reason, and provider metadata belong to stream parts, matching the
/// AI SDK provider contract.
pub(all) struct LanguageModelV4StreamResult {
  request : RequestMetadata?
  response : ResponseMetadata?
} derive(Debug)

///|
/// Construct a V4 stream result.
pub fn LanguageModelV4StreamResult::new(
  request : RequestMetadata?,
  response : ResponseMetadata?,
) -> LanguageModelV4StreamResult {
  { request, response }
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
