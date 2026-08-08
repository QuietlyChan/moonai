///|
/// Final values collected by the high-level `streamText` workflow.
///
/// MoonBit consumes the provider stream before this value is returned, so the
/// AI SDK promise-backed fields are represented directly. Content, calls,
/// results, warnings, messages, and usage are aggregated across all steps;
/// request, response, finish reason, and provider metadata come from the final
/// step.
pub(all) struct StreamTextResult {
  content : Array[GenerateTextContent]
  tool_calls : Array[GenerateTextToolCall]
  tool_results : Array[GenerateTextToolResult]
  tool_approval_requests : Array[GenerateTextToolApprovalRequestOutput]
  tool_approval_responses : Array[GenerateTextToolApprovalResponseOutput]
  files : Array[@provider.LanguageModelV4File]
  sources : Array[@provider.LanguageModelV4Source]
  finish_reason : @provider.LanguageModelV4FinishReason
  usage : @provider.LanguageModelV4Usage
  total_usage : @provider.LanguageModelV4Usage
  warnings : Array[@provider.Warning]
  request : @provider.RequestMetadata?
  response : @provider.ResponseMetadata?
  response_messages : Array[@provider_utils.ModelMessage]
  provider_metadata : Map[String, Json]
  steps : Array[GenerateTextStep]
  final_step : GenerateTextStep
} derive(Debug)

///|
fn create_stream_text_result(
  steps : Array[GenerateTextStep],
) -> StreamTextResult {
  let result = create_generate_text_result(steps)
  {
    content: result.content,
    tool_calls: result.tool_calls,
    tool_results: result.tool_results,
    tool_approval_requests: result.tool_approval_requests,
    tool_approval_responses: result.tool_approval_responses,
    files: result.files,
    sources: result.sources,
    finish_reason: result.finish_reason,
    usage: result.usage,
    total_usage: result.total_usage,
    warnings: result.warnings,
    request: result.request,
    response: result.response,
    response_messages: result.response_messages,
    provider_metadata: result.provider_metadata,
    steps: result.steps,
    final_step: result.final_step,
  }
}

///|
/// Return concatenated text generated in the final streamed step.
pub fn StreamTextResult::text(self : StreamTextResult) -> String {
  self.final_step.text()
}

///|
/// Return concatenated reasoning generated in the final streamed step.
pub fn StreamTextResult::reasoning(self : StreamTextResult) -> String {
  self.final_step.reasoning()
}

///|
/// Return the normalized provider result assembled for the final stream step.
pub fn StreamTextResult::provider_result(
  self : StreamTextResult,
) -> @provider.LanguageModelV4GenerateResult {
  self.final_step.provider_result
}

///|
/// Convert the final streamed provider result to a normalized chat response.
pub fn StreamTextResult::to_chat_response(
  self : StreamTextResult,
) -> @provider.ChatResponse {
  self.final_step.provider_result.to_chat_response()
}
