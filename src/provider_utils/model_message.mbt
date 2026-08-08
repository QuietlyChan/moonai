///|
/// A user-facing content part accepted by high-level AI workflows.
///
/// This type is intentionally distinct from
/// `provider::LanguageModelContentPart`. The `ai/prompt` package validates and
/// converts model messages before a provider sees them.
pub(all) enum ModelContentPart {
  ModelText(String)
  ModelImageUrl(String)
  ModelImageData(data~ : String, media_type~ : String)
  ModelAudioData(data~ : String, format~ : String)
  ModelFileUrl(url~ : String, media_type~ : String, filename~ : String)
  ModelFileData(data~ : String, media_type~ : String, filename~ : String)
  ModelFileReference(
    reference~ : @provider.ProviderReference,
    media_type~ : String,
    filename~ : String
  )
  ModelReasoning(String)
  ModelReasoningFileUrl(url~ : String, media_type~ : String)
  ModelReasoningFileData(data~ : String, media_type~ : String)
  ModelCustom(kind~ : String)
  ModelToolCallPart(call~ : ModelToolCall)
  ModelToolResultPart(result~ : ModelToolResult)
  ModelToolApprovalRequestPart(request~ : ModelToolApprovalRequest)
  ModelToolApprovalResponsePart(response~ : ModelToolApprovalResponse)
  ModelPartProviderOptions(
    part~ : ModelContentPart,
    options~ : Map[String, Json]
  )
} derive(Debug, Eq)

///|
/// Construct a text part.
pub fn ModelContentPart::text(value : String) -> ModelContentPart {
  ModelText(value)
}

///|
/// Construct an image URL part.
pub fn ModelContentPart::image_url(value : String) -> ModelContentPart {
  ModelImageUrl(value)
}

///|
/// Construct an inline base64 image part.
pub fn ModelContentPart::image_data(
  data~ : String,
  media_type~ : String,
) -> ModelContentPart {
  ModelImageData(data~, media_type~)
}

///|
/// Construct an inline base64 audio part.
pub fn ModelContentPart::audio_data(
  data~ : String,
  format~ : String,
) -> ModelContentPart {
  ModelAudioData(data~, format~)
}

///|
/// Construct a URL-backed file part.
pub fn ModelContentPart::file_url(
  url~ : String,
  media_type? : String = "application/octet-stream",
  filename? : String = "",
) -> ModelContentPart {
  ModelFileUrl(url~, media_type~, filename~)
}

///|
/// Construct an inline base64 file part.
pub fn ModelContentPart::file_data(
  data~ : String,
  media_type~ : String,
  filename~ : String,
) -> ModelContentPart {
  ModelFileData(data~, media_type~, filename~)
}

///|
/// Construct a provider-reference-backed file part.
pub fn ModelContentPart::file_reference(
  reference~ : @provider.ProviderReference,
  media_type? : String = "application/octet-stream",
  filename? : String = "",
) -> ModelContentPart {
  ModelFileReference(reference~, media_type~, filename~)
}

///|
/// Construct a reasoning text part.
pub fn ModelContentPart::reasoning(value : String) -> ModelContentPart {
  ModelReasoning(value)
}

///|
/// Construct a URL-backed reasoning file part.
pub fn ModelContentPart::reasoning_file_url(
  url~ : String,
  media_type~ : String,
) -> ModelContentPart {
  ModelReasoningFileUrl(url~, media_type~)
}

///|
/// Construct a base64 reasoning file part.
pub fn ModelContentPart::reasoning_file_data(
  data~ : String,
  media_type~ : String,
) -> ModelContentPart {
  ModelReasoningFileData(data~, media_type~)
}

///|
/// Construct a provider-specific custom content part.
pub fn ModelContentPart::custom(kind : String) -> ModelContentPart {
  ModelCustom(kind~)
}

///|
fn copy_model_provider_options(
  options : Map[String, Json],
) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for entry in options.iter2() {
    result[entry.0] = entry.1
  }
  result
}

///|
fn merge_model_provider_options(
  base : Map[String, Json],
  extra : Map[String, Json],
) -> Map[String, Json] {
  let result = copy_model_provider_options(base)
  for entry in extra.iter2() {
    result[entry.0] = entry.1
  }
  result
}

///|
/// Attach provider-specific options to a user-facing content part.
pub fn ModelContentPart::with_provider_options(
  self : ModelContentPart,
  options : Map[String, Json],
) -> ModelContentPart {
  guard options.length() > 0 else { return self }
  match self {
    ModelPartProviderOptions(part~, options=existing) =>
      ModelPartProviderOptions(
        part=part.without_provider_options(),
        options=merge_model_provider_options(existing, options),
      )
    _ => ModelPartProviderOptions(part=self, options~)
  }
}

///|
/// Return provider-specific options attached to a content part.
pub fn ModelContentPart::provider_options(
  self : ModelContentPart,
) -> Map[String, Json] {
  match self {
    ModelPartProviderOptions(options~, ..) =>
      copy_model_provider_options(options)
    _ => Map([])
  }
}

///|
/// Remove a provider-options wrapper from a content part.
pub fn ModelContentPart::without_provider_options(
  self : ModelContentPart,
) -> ModelContentPart {
  match self {
    ModelPartProviderOptions(part~, ..) => part.without_provider_options()
    _ => self
  }
}

///|
/// A tool call included in a user-facing assistant history message.
///
/// Inputs are JSON values at this layer. Conversion to a provider prompt is
/// responsible for producing the serialized argument form used by current
/// provider adapters.
pub(all) struct ModelToolCall {
  id : String
  name : String
  input : Json
  provider_executed : Bool
  dynamic : Bool
  provider_options : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a tool call for an assistant history message.
pub fn ModelToolCall::new(
  id~ : String,
  name~ : String,
  input~ : Json,
  provider_executed? : Bool = false,
  dynamic? : Bool = false,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolCall {
  {
    id,
    name,
    input,
    provider_executed,
    dynamic,
    provider_options: copy_model_provider_options(provider_options),
  }
}

///|
/// A tool-result content part returned by a client or provider-executed tool.
pub(all) enum ModelToolResultContentPart {
  ModelToolResultText(text~ : String, provider_options~ : Map[String, Json])
  ModelToolResultFileUrl(
    url~ : String,
    media_type~ : String,
    filename~ : String,
    provider_options~ : Map[String, Json]
  )
  ModelToolResultFileData(
    data~ : String,
    media_type~ : String,
    filename~ : String,
    provider_options~ : Map[String, Json]
  )
  ModelToolResultFileReference(
    reference~ : @provider.ProviderReference,
    media_type~ : String,
    filename~ : String,
    provider_options~ : Map[String, Json]
  )
  ModelToolResultCustom(provider_options~ : Map[String, Json])
} derive(Debug, Eq)

///|
/// The normalized output shape of a tool result.
pub(all) enum ModelToolResultOutput {
  ModelToolText(value~ : String, provider_options~ : Map[String, Json])
  ModelToolJson(value~ : Json, provider_options~ : Map[String, Json])
  ModelToolExecutionDenied(
    reason~ : String?,
    provider_options~ : Map[String, Json]
  )
  ModelToolErrorText(value~ : String, provider_options~ : Map[String, Json])
  ModelToolErrorJson(value~ : Json, provider_options~ : Map[String, Json])
  ModelToolContent(
    value~ : Array[ModelToolResultContentPart],
    provider_options~ : Map[String, Json]
  )
} derive(Debug, Eq)

///|
/// Construct a text model output for a tool result.
pub fn ModelToolResultOutput::text(
  value : String,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResultOutput {
  ModelToolText(
    value~,
    provider_options=copy_model_provider_options(provider_options),
  )
}

///|
/// Construct a JSON model output for a tool result.
pub fn ModelToolResultOutput::json(
  value : Json,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResultOutput {
  ModelToolJson(
    value~,
    provider_options=copy_model_provider_options(provider_options),
  )
}

///|
/// Construct an execution-denied model output for a tool result.
pub fn ModelToolResultOutput::execution_denied(
  reason? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResultOutput {
  ModelToolExecutionDenied(
    reason~,
    provider_options=copy_model_provider_options(provider_options),
  )
}

///|
/// Construct a text error model output for a tool result.
pub fn ModelToolResultOutput::error_text(
  value : String,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResultOutput {
  ModelToolErrorText(
    value~,
    provider_options=copy_model_provider_options(provider_options),
  )
}

///|
/// Construct a JSON error model output for a tool result.
pub fn ModelToolResultOutput::error_json(
  value : Json,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResultOutput {
  ModelToolErrorJson(
    value~,
    provider_options=copy_model_provider_options(provider_options),
  )
}

///|
/// Construct a multimodal model output for a tool result.
pub fn ModelToolResultOutput::content(
  value : Array[ModelToolResultContentPart],
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResultOutput {
  ModelToolContent(
    value=value.copy(),
    provider_options=copy_model_provider_options(provider_options),
  )
}

///|
/// A tool result in a user-facing model message.
pub(all) struct ModelToolResult {
  tool_call_id : String
  tool_name : String
  output : ModelToolResultOutput
  provider_options : Map[String, Json]
} derive(Debug, Eq)

///|
/// A provider-executed tool approval request in an assistant message.
pub(all) struct ModelToolApprovalRequest {
  approval_id : String
  tool_call_id : String
  is_automatic : Bool
  signature : String?
} derive(Debug, Eq)

///|
/// A tool approval response in a tool message.
pub(all) struct ModelToolApprovalResponse {
  approval_id : String
  approved : Bool
  reason : String?
  provider_executed : Bool
  provider_options : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a text tool result.
pub fn ModelToolResult::text(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResult {
  {
    tool_call_id,
    tool_name,
    output: ModelToolText(
      value~,
      provider_options=copy_model_provider_options(provider_options),
    ),
    provider_options: copy_model_provider_options(provider_options),
  }
}

///|
/// Construct a JSON tool result.
pub fn ModelToolResult::json(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : Json,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResult {
  {
    tool_call_id,
    tool_name,
    output: ModelToolJson(
      value~,
      provider_options=copy_model_provider_options(provider_options),
    ),
    provider_options: copy_model_provider_options(provider_options),
  }
}

///|
/// Construct an execution-denied tool result.
pub fn ModelToolResult::execution_denied(
  tool_call_id~ : String,
  tool_name~ : String,
  reason? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResult {
  {
    tool_call_id,
    tool_name,
    output: ModelToolExecutionDenied(
      reason~,
      provider_options=copy_model_provider_options(provider_options),
    ),
    provider_options: copy_model_provider_options(provider_options),
  }
}

///|
/// Construct a text item inside a multimodal tool result.
pub fn ModelToolResultContentPart::text(
  text : String,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResultContentPart {
  ModelToolResultText(
    text~,
    provider_options=copy_model_provider_options(provider_options),
  )
}

///|
/// Construct a URL-backed file item inside a multimodal tool result.
pub fn ModelToolResultContentPart::file_url(
  url~ : String,
  media_type~ : String,
  filename? : String = "",
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResultContentPart {
  ModelToolResultFileUrl(
    url~,
    media_type~,
    filename~,
    provider_options=copy_model_provider_options(provider_options),
  )
}

///|
/// Construct a base64 file item inside a multimodal tool result.
pub fn ModelToolResultContentPart::file_data(
  data~ : String,
  media_type~ : String,
  filename? : String = "",
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResultContentPart {
  ModelToolResultFileData(
    data~,
    media_type~,
    filename~,
    provider_options=copy_model_provider_options(provider_options),
  )
}

///|
/// Construct a provider-reference-backed file item inside a tool result.
pub fn ModelToolResultContentPart::file_reference(
  reference~ : @provider.ProviderReference,
  media_type~ : String,
  filename? : String = "",
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResultContentPart {
  ModelToolResultFileReference(
    reference~,
    media_type~,
    filename~,
    provider_options=copy_model_provider_options(provider_options),
  )
}

///|
/// Construct a provider-specific custom item inside a tool result.
pub fn ModelToolResultContentPart::custom(
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResultContentPart {
  ModelToolResultCustom(
    provider_options=copy_model_provider_options(provider_options),
  )
}

///|
/// Construct a multimodal tool result.
pub fn ModelToolResult::content(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : Array[ModelToolResultContentPart],
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResult {
  {
    tool_call_id,
    tool_name,
    output: ModelToolContent(
      value~,
      provider_options=copy_model_provider_options(provider_options),
    ),
    provider_options: copy_model_provider_options(provider_options),
  }
}

///|
/// Construct an error-text tool result.
pub fn ModelToolResult::error_text(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResult {
  {
    tool_call_id,
    tool_name,
    output: ModelToolErrorText(
      value~,
      provider_options=copy_model_provider_options(provider_options),
    ),
    provider_options: copy_model_provider_options(provider_options),
  }
}

///|
/// Construct an error-JSON tool result.
pub fn ModelToolResult::error_json(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : Json,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolResult {
  {
    tool_call_id,
    tool_name,
    output: ModelToolErrorJson(
      value~,
      provider_options=copy_model_provider_options(provider_options),
    ),
    provider_options: copy_model_provider_options(provider_options),
  }
}

///|
/// Construct an approval request.
pub fn ModelToolApprovalRequest::new(
  approval_id~ : String,
  tool_call_id~ : String,
  is_automatic? : Bool = false,
  signature? : String,
) -> ModelToolApprovalRequest {
  { approval_id, tool_call_id, is_automatic, signature }
}

///|
/// Construct an approval response.
pub fn ModelToolApprovalResponse::new(
  approval_id~ : String,
  approved~ : Bool,
  reason? : String,
  provider_executed? : Bool = false,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelToolApprovalResponse {
  {
    approval_id,
    approved,
    reason,
    provider_executed,
    provider_options: copy_model_provider_options(provider_options),
  }
}

///|
/// Construct a tool-call content part.
pub fn ModelContentPart::tool_call(call : ModelToolCall) -> ModelContentPart {
  ModelToolCallPart(call~)
}

///|
/// Construct a tool-result content part.
pub fn ModelContentPart::tool_result(
  result : ModelToolResult,
) -> ModelContentPart {
  ModelToolResultPart(result~)
}

///|
/// Construct a tool-approval request content part.
pub fn ModelContentPart::tool_approval_request(
  request : ModelToolApprovalRequest,
) -> ModelContentPart {
  ModelToolApprovalRequestPart(request~)
}

///|
/// Construct a tool-approval response content part.
pub fn ModelContentPart::tool_approval_response(
  response : ModelToolApprovalResponse,
) -> ModelContentPart {
  ModelToolApprovalResponsePart(response~)
}

///|
/// Role of a user-facing model message.
pub(all) enum ModelMessageRole {
  ModelSystem
  ModelUser
  ModelAssistant
  ModelTool(String)
} derive(Debug, Eq)

///|
/// A user-facing prompt message.
///
/// Role-specific constructors prevent provider-facing messages from being
/// passed directly to high-level workflows. The richer public representation
/// can evolve independently of provider wire contracts.
pub(all) struct ModelMessage {
  role : ModelMessageRole
  content : String
  parts : Array[ModelContentPart]
  tool_calls : Array[ModelToolCall]
  reasoning_content : String?
  provider_options : Map[String, Json]
} derive(Debug, Eq)

///|
fn new_model_message(
  role : ModelMessageRole,
  content : String,
  parts : Array[ModelContentPart],
  tool_calls : Array[ModelToolCall],
  reasoning_content : String?,
  provider_options : Map[String, Json],
) -> ModelMessage {
  {
    role,
    content,
    parts: parts.copy(),
    tool_calls: tool_calls.copy(),
    reasoning_content,
    provider_options: copy_model_provider_options(provider_options),
  }
}

///|
/// Construct a system message.
pub fn ModelMessage::system(
  content : String,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelMessage {
  new_model_message(ModelSystem, content, [], [], None, provider_options)
}

///|
/// Construct a user text message.
pub fn ModelMessage::user(
  content : String,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelMessage {
  new_model_message(ModelUser, content, [], [], None, provider_options)
}

///|
/// Construct a user message from content parts.
pub fn ModelMessage::user_parts(
  parts : Array[ModelContentPart],
  provider_options? : Map[String, Json] = Map([]),
) -> ModelMessage {
  new_model_message(ModelUser, "", parts, [], None, provider_options)
}

///|
/// Construct an assistant text message.
pub fn ModelMessage::assistant(
  content : String,
  tool_calls? : Array[ModelToolCall] = [],
  reasoning_content? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelMessage {
  new_model_message(
    ModelAssistant,
    content,
    [],
    tool_calls,
    reasoning_content,
    provider_options,
  )
}

///|
/// Construct an assistant message from content parts.
pub fn ModelMessage::assistant_parts(
  parts : Array[ModelContentPart],
  tool_calls? : Array[ModelToolCall] = [],
  reasoning_content? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelMessage {
  new_model_message(
    ModelAssistant,
    "",
    parts,
    tool_calls,
    reasoning_content,
    provider_options,
  )
}

///|
/// Construct a text tool-result message.
pub fn ModelMessage::tool(
  tool_call_id : String,
  content : String,
  provider_options? : Map[String, Json] = Map([]),
) -> ModelMessage {
  new_model_message(
    ModelTool(tool_call_id),
    content,
    [],
    [],
    None,
    provider_options,
  )
}

///|
/// Construct a content-part tool-result message.
pub fn ModelMessage::tool_parts(
  tool_call_id : String,
  parts : Array[ModelContentPart],
  provider_options? : Map[String, Json] = Map([]),
) -> ModelMessage {
  new_model_message(
    ModelTool(tool_call_id),
    "",
    parts,
    [],
    None,
    provider_options,
  )
}

///|
/// Construct a tool message containing results or approval responses without
/// forcing all parts to share one tool-call id.
pub fn ModelMessage::tool_content(
  parts : Array[ModelContentPart],
  provider_options? : Map[String, Json] = Map([]),
) -> ModelMessage {
  new_model_message(ModelTool(""), "", parts, [], None, provider_options)
}

///|
/// Return a deep-enough copy for prompt standardization and rewriting.
pub fn ModelMessage::copy(self : ModelMessage) -> ModelMessage {
  new_model_message(
    self.role,
    self.content,
    self.parts,
    self.tool_calls,
    self.reasoning_content,
    self.provider_options,
  )
}

///|
/// Return a copy with replacement content parts.
pub fn ModelMessage::with_parts(
  self : ModelMessage,
  parts : Array[ModelContentPart],
) -> ModelMessage {
  new_model_message(
    self.role,
    self.content,
    parts,
    self.tool_calls,
    self.reasoning_content,
    self.provider_options,
  )
}

///|
/// Add or merge message-level provider options.
pub fn ModelMessage::with_provider_options(
  self : ModelMessage,
  options : Map[String, Json],
) -> ModelMessage {
  new_model_message(
    self.role,
    self.content,
    self.parts,
    self.tool_calls,
    self.reasoning_content,
    merge_model_provider_options(self.provider_options, options),
  )
}
