///|
/// A parsed tool call exposed by the high-level generation workflow.
pub(all) struct GenerateTextToolCall {
  tool_call_id : String
  tool_name : String
  input : Json
  input_text : String
  provider_executed : Bool
  dynamic : Bool
  invalid : Bool
  error : String?
  provider_metadata : Map[String, Json]
} derive(Debug, Eq)

///|
/// A client- or provider-executed tool result exposed by the high-level
/// generation workflow.
pub(all) struct GenerateTextToolResult {
  tool_call_id : String
  tool_name : String
  input : Json
  output : Json
  is_error : Bool
  preliminary : Bool
  provider_executed : Bool
  dynamic : Bool
  provider_metadata : Map[String, Json]
} derive(Debug, Eq)

///|
/// High-level request for approval of a parsed tool call.
pub(all) struct GenerateTextToolApprovalRequestOutput {
  approval_id : String
  tool_call : GenerateTextToolCall
  is_automatic : Bool
  signature : String?
  provider_metadata : Map[String, Json]
} derive(Debug, Eq)

///|
/// High-level response to a tool approval request.
pub(all) struct GenerateTextToolApprovalResponseOutput {
  approval_id : String
  tool_call : GenerateTextToolCall
  approved : Bool
  reason : String?
  provider_executed : Bool
} derive(Debug, Eq)

///|
/// Ordered high-level content produced by `generateText`.
///
/// Provider V4 parts are normalized into this vocabulary before tool
/// execution results are added. This keeps the provider contract separate
/// from the high-level multi-step result.
pub(all) enum GenerateTextContent {
  GenerateTextText(@provider.LanguageModelV4Text)
  GenerateTextReasoning(@provider.LanguageModelV4Reasoning)
  GenerateTextCustom(@provider.LanguageModelV4CustomContent)
  GenerateTextReasoningFile(@provider.LanguageModelV4ReasoningFile)
  GenerateTextFile(@provider.LanguageModelV4File)
  GenerateTextToolApprovalRequest(GenerateTextToolApprovalRequestOutput)
  GenerateTextToolApprovalResponse(GenerateTextToolApprovalResponseOutput)
  GenerateTextSource(@provider.LanguageModelV4Source)
  GenerateTextToolCall(GenerateTextToolCall)
  GenerateTextToolResult(GenerateTextToolResult)
} derive(Debug, Eq)

///|
/// Performance metrics for one non-streaming language-model step.
pub(all) struct GenerateTextStepPerformance {
  step_time_ms : Int
  response_time_ms : Int
  tool_execution_ms : Map[String, Int]
  effective_output_tokens_per_second : Double?
  effective_total_tokens_per_second : Double?
} derive(Debug, Eq)

///|
/// Details for one language-model call in a multi-step generation.
pub(all) struct GenerateTextStep {
  call_id : String
  step_number : Int
  provider : String
  model_id : String
  runtime_context : Json
  tools_context : Map[String, Json]
  content : Array[GenerateTextContent]
  tool_calls : Array[GenerateTextToolCall]
  tool_results : Array[GenerateTextToolResult]
  tool_approval_requests : Array[GenerateTextToolApprovalRequestOutput]
  tool_approval_responses : Array[GenerateTextToolApprovalResponseOutput]
  finish_reason : @provider.LanguageModelV4FinishReason
  usage : @provider.LanguageModelV4Usage
  performance : GenerateTextStepPerformance
  request : @provider.RequestMetadata?
  response : @provider.ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[@provider.Warning]
  response_messages : Array[@provider_utils.ModelMessage]
  provider_result : @provider.LanguageModelV4GenerateResult
} derive(Debug)

///|
fn content_text(content : Array[GenerateTextContent]) -> String {
  let output = StringBuilder::new()
  for part in content {
    match part {
      GenerateTextText(value) => output.write_string(value.text)
      _ => ()
    }
  }
  output.to_string()
}

///|
fn content_reasoning(content : Array[GenerateTextContent]) -> String {
  let output = StringBuilder::new()
  for part in content {
    match part {
      GenerateTextReasoning(value) => output.write_string(value.text)
      _ => ()
    }
  }
  output.to_string()
}

///|
/// Return concatenated text generated in this step.
pub fn GenerateTextStep::text(self : GenerateTextStep) -> String {
  content_text(self.content)
}

///|
/// Return concatenated reasoning text generated in this step.
pub fn GenerateTextStep::reasoning(self : GenerateTextStep) -> String {
  content_reasoning(self.content)
}

///|
/// High-level result of `generateText`.
pub(all) struct GenerateTextResult {
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
fn create_generate_text_result(
  steps : Array[GenerateTextStep],
) -> GenerateTextResult {
  let final_step = steps[steps.length() - 1]
  let content : Array[GenerateTextContent] = []
  let tool_calls : Array[GenerateTextToolCall] = []
  let tool_results : Array[GenerateTextToolResult] = []
  let tool_approval_requests : Array[GenerateTextToolApprovalRequestOutput] = []
  let tool_approval_responses : Array[GenerateTextToolApprovalResponseOutput] = []
  let files : Array[@provider.LanguageModelV4File] = []
  let sources : Array[@provider.LanguageModelV4Source] = []
  let warnings : Array[@provider.Warning] = []
  let response_messages : Array[@provider_utils.ModelMessage] = []
  let mut usage = @provider.LanguageModelV4Usage::unknown()
  for step in steps {
    for part in step.content {
      content.push(part)
      match part {
        GenerateTextFile(file) => files.push(file)
        GenerateTextSource(source) => sources.push(source)
        GenerateTextToolApprovalRequest(request) =>
          tool_approval_requests.push(request)
        GenerateTextToolApprovalResponse(response) =>
          tool_approval_responses.push(response)
        _ => ()
      }
    }
    for call in step.tool_calls {
      tool_calls.push(call)
    }
    for result in step.tool_results {
      tool_results.push(result)
    }
    for warning in step.warnings {
      warnings.push(warning)
    }
    for message in step.response_messages {
      response_messages.push(message.copy())
    }
    usage = @provider_utils.add_language_model_usage(usage, step.usage)
  }
  {
    content,
    tool_calls,
    tool_results,
    tool_approval_requests,
    tool_approval_responses,
    files,
    sources,
    finish_reason: final_step.finish_reason,
    usage,
    total_usage: usage,
    warnings,
    request: final_step.request,
    response: final_step.response,
    response_messages,
    provider_metadata: @provider.copy_provider_metadata(
      final_step.provider_metadata,
    ),
    steps: steps.copy(),
    final_step,
  }
}

///|
/// Return text generated in the final step.
pub fn GenerateTextResult::text(self : GenerateTextResult) -> String {
  self.final_step.text()
}

///|
/// Return reasoning text generated in the final step.
pub fn GenerateTextResult::reasoning(self : GenerateTextResult) -> String {
  self.final_step.reasoning()
}

///|
/// Return the provider result that produced the final step.
pub fn GenerateTextResult::provider_result(
  self : GenerateTextResult,
) -> @provider.LanguageModelV4GenerateResult {
  self.final_step.provider_result
}

///|
/// Convert the final provider result to the normalized chat response.
pub fn GenerateTextResult::to_chat_response(
  self : GenerateTextResult,
) -> @provider.ChatResponse {
  self.final_step.provider_result.to_chat_response()
}

///|
/// Error raised when a client tool call names no registered tool.
pub(all) suberror NoSuchToolError {
  NoSuchToolError(tool_name~ : String, available_tools~ : Array[String])
} derive(Debug, Eq)

///|
/// Error raised when a static tool call contains invalid input.
pub(all) suberror InvalidToolInputError {
  InvalidToolInputError(
    tool_call_id~ : String,
    tool_name~ : String,
    input~ : String,
    message~ : String
  )
} derive(Debug, Eq)

///|
/// Error raised when an approval response has no matching request.
pub(all) suberror InvalidToolApprovalError {
  InvalidToolApprovalError(approval_id~ : String)
} derive(Debug, Eq)

///|
/// Error raised when a signed approval request cannot be authenticated.
pub suberror InvalidToolApprovalSignatureError {
  InvalidToolApprovalSignatureError(
    approval_id~ : String,
    tool_call_id~ : String,
    reason~ : String
  )
} derive(Debug, Eq)

///|
/// Error raised when an approval request refers to no prior tool call.
pub(all) suberror ToolCallNotFoundForApprovalError {
  ToolCallNotFoundForApprovalError(
    tool_call_id~ : String,
    approval_id~ : String
  )
} derive(Debug, Eq)
