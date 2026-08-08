///|
/// Tagged file data used by a V4 prompt.
///
/// The data variant mirrors AI SDK's `Uint8Array | string` payload without
/// forcing callers to Base64 encode raw bytes before reaching a provider.
pub(all) enum LanguageModelV4FileData {
  V4FileData(String)
  V4FileBytes(Bytes)
  V4FileUrl(String)
  V4FileReference(ProviderReference)
  V4FileText(String)
} derive(Debug, Eq)

///|
/// A tool call carried in V4 prompt history.
///
/// Prompt tool input is structured JSON. Generated V4 tool calls keep their
/// string input separately because provider responses arrive incrementally.
pub(all) struct LanguageModelV4ToolCallPart {
  tool_call_id : String
  tool_name : String
  input : Json
  provider_executed : Bool
  provider_options : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a V4 prompt tool call.
pub fn LanguageModelV4ToolCallPart::new(
  tool_call_id~ : String,
  tool_name~ : String,
  input~ : Json,
  provider_executed? : Bool = false,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelV4ToolCallPart {
  {
    tool_call_id,
    tool_name,
    input,
    provider_executed,
    provider_options: copy_provider_metadata(provider_options),
  }
}

///|
/// Content embedded in a V4 prompt tool-result output.
pub(all) enum LanguageModelV4ToolResultContentPart {
  V4ToolResultTextContent(text~ : String, provider_options~ : Map[String, Json])
  V4ToolResultFileContent(
    data~ : LanguageModelV4FileData,
    media_type~ : String,
    filename~ : String?,
    provider_options~ : Map[String, Json]
  )
  V4ToolResultCustomContent(provider_options~ : Map[String, Json])
} derive(Debug, Eq)

///|
/// Construct text content embedded in a V4 tool result.
pub fn LanguageModelV4ToolResultContentPart::text(
  text : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelV4ToolResultContentPart {
  V4ToolResultTextContent(
    text~,
    provider_options=copy_provider_metadata(provider_options),
  )
}

///|
/// Construct file content embedded in a V4 tool result.
pub fn LanguageModelV4ToolResultContentPart::file(
  data~ : LanguageModelV4FileData,
  media_type~ : String,
  filename? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelV4ToolResultContentPart {
  V4ToolResultFileContent(
    data~,
    media_type~,
    filename~,
    provider_options=copy_provider_metadata(provider_options),
  )
}

///|
/// Construct provider-specific content embedded in a V4 tool result.
pub fn LanguageModelV4ToolResultContentPart::custom(
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelV4ToolResultContentPart {
  V4ToolResultCustomContent(
    provider_options=copy_provider_metadata(provider_options),
  )
}

///|
/// Standardized output shape of a V4 prompt tool result.
pub(all) enum LanguageModelV4ToolResultOutput {
  V4ToolResultTextOutput(value~ : String, provider_options~ : Map[String, Json])
  V4ToolResultJsonOutput(value~ : Json, provider_options~ : Map[String, Json])
  V4ToolResultExecutionDenied(
    reason~ : String?,
    provider_options~ : Map[String, Json]
  )
  V4ToolResultErrorText(value~ : String, provider_options~ : Map[String, Json])
  V4ToolResultErrorJson(value~ : Json, provider_options~ : Map[String, Json])
  V4ToolResultContentOutput(
    value~ : Array[LanguageModelV4ToolResultContentPart],
    provider_options~ : Map[String, Json]
  )
} derive(Debug, Eq)

///|
/// A tool result carried in V4 prompt history.
pub(all) struct LanguageModelV4ToolResultPart {
  tool_call_id : String
  tool_name : String
  output : LanguageModelV4ToolResultOutput
  provider_options : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a V4 text tool result.
pub fn LanguageModelV4ToolResultPart::text(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelV4ToolResultPart {
  let options = copy_provider_metadata(provider_options)
  {
    tool_call_id,
    tool_name,
    output: V4ToolResultTextOutput(
      value~,
      provider_options=copy_provider_metadata(options),
    ),
    provider_options: options,
  }
}

///|
/// Construct a V4 JSON tool result.
pub fn LanguageModelV4ToolResultPart::json(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : Json,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelV4ToolResultPart {
  let options = copy_provider_metadata(provider_options)
  {
    tool_call_id,
    tool_name,
    output: V4ToolResultJsonOutput(
      value~,
      provider_options=copy_provider_metadata(options),
    ),
    provider_options: options,
  }
}

///|
/// Construct a denied V4 tool result.
pub fn LanguageModelV4ToolResultPart::execution_denied(
  tool_call_id~ : String,
  tool_name~ : String,
  reason? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelV4ToolResultPart {
  let options = copy_provider_metadata(provider_options)
  {
    tool_call_id,
    tool_name,
    output: V4ToolResultExecutionDenied(
      reason~,
      provider_options=copy_provider_metadata(options),
    ),
    provider_options: options,
  }
}

///|
/// Construct a multimodal V4 tool result.
pub fn LanguageModelV4ToolResultPart::content(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : Array[LanguageModelV4ToolResultContentPart],
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelV4ToolResultPart {
  let options = copy_provider_metadata(provider_options)
  {
    tool_call_id,
    tool_name,
    output: V4ToolResultContentOutput(
      value~,
      provider_options=copy_provider_metadata(options),
    ),
    provider_options: options,
  }
}

///|
/// Construct a V4 text error tool result.
pub fn LanguageModelV4ToolResultPart::error_text(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelV4ToolResultPart {
  let options = copy_provider_metadata(provider_options)
  {
    tool_call_id,
    tool_name,
    output: V4ToolResultErrorText(
      value~,
      provider_options=copy_provider_metadata(options),
    ),
    provider_options: options,
  }
}

///|
/// Construct a V4 JSON error tool result.
pub fn LanguageModelV4ToolResultPart::error_json(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : Json,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelV4ToolResultPart {
  let options = copy_provider_metadata(provider_options)
  {
    tool_call_id,
    tool_name,
    output: V4ToolResultErrorJson(
      value~,
      provider_options=copy_provider_metadata(options),
    ),
    provider_options: options,
  }
}

///|
/// A provider-executed tool approval response carried in V4 prompt history.
pub(all) struct LanguageModelV4ToolApprovalResponsePart {
  approval_id : String
  approved : Bool
  reason : String?
  provider_options : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a V4 tool approval response.
pub fn LanguageModelV4ToolApprovalResponsePart::new(
  approval_id~ : String,
  approved~ : Bool,
  reason? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelV4ToolApprovalResponsePart {
  {
    approval_id,
    approved,
    reason,
    provider_options: copy_provider_metadata(provider_options),
  }
}

///|
/// Standardized content part used by V4 prompt messages.
pub(all) enum LanguageModelV4PromptPart {
  V4PromptText(text~ : String, provider_options~ : Map[String, Json])
  V4PromptReasoning(text~ : String, provider_options~ : Map[String, Json])
  V4PromptReasoningFile(
    data~ : LanguageModelV4FileData,
    media_type~ : String,
    provider_options~ : Map[String, Json]
  )
  V4PromptCustom(kind~ : String, provider_options~ : Map[String, Json])
  V4PromptFile(
    data~ : LanguageModelV4FileData,
    media_type~ : String,
    filename~ : String?,
    provider_options~ : Map[String, Json]
  )
  V4PromptToolCall(LanguageModelV4ToolCallPart)
  V4PromptToolResult(LanguageModelV4ToolResultPart)
  V4PromptToolApprovalResponse(LanguageModelV4ToolApprovalResponsePart)
} derive(Debug, Eq)

///|
fn legacy_tool_input(arguments : String) -> Json {
  @json.parse(arguments) catch {
    _ => Json::string(arguments)
  }
}

///|
fn LanguageModelV4ToolCallPart::from_tool_call(
  call : ToolCall,
) -> LanguageModelV4ToolCallPart {
  LanguageModelV4ToolCallPart::new(
    tool_call_id=call.id,
    tool_name=call.name,
    input=legacy_tool_input(call.arguments),
    provider_executed=call.provider_executed,
    provider_options=call.provider_metadata,
  )
}

///|
fn LanguageModelV4ToolCallPart::to_tool_call(
  self : LanguageModelV4ToolCallPart,
) -> ToolCall {
  ToolCall::new(
    id=self.tool_call_id,
    name=self.tool_name,
    arguments=self.input.stringify(),
    provider_executed=self.provider_executed,
    provider_metadata=copy_provider_metadata(self.provider_options),
  )
}

///|
fn LanguageModelV4ToolResultContentPart::from_legacy(
  part : LanguageModelToolResultContentPart,
) -> LanguageModelV4ToolResultContentPart {
  match part {
    LanguageModelToolText(text~, provider_options~) =>
      V4ToolResultTextContent(
        text~,
        provider_options=copy_provider_metadata(provider_options),
      )
    LanguageModelToolFileUrl(url~, media_type~, filename~, provider_options~) =>
      V4ToolResultFileContent(
        data=V4FileUrl(url),
        media_type~,
        filename=if filename == "" { None } else { Some(filename) },
        provider_options=copy_provider_metadata(provider_options),
      )
    LanguageModelToolFileData(data~, media_type~, filename~, provider_options~) =>
      V4ToolResultFileContent(
        data=V4FileData(data),
        media_type~,
        filename=if filename == "" { None } else { Some(filename) },
        provider_options=copy_provider_metadata(provider_options),
      )
    LanguageModelToolFileReference(
      reference~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      V4ToolResultFileContent(
        data=V4FileReference(reference),
        media_type~,
        filename=if filename == "" { None } else { Some(filename) },
        provider_options=copy_provider_metadata(provider_options),
      )
    LanguageModelToolCustom(provider_options~) =>
      V4ToolResultCustomContent(
        provider_options=copy_provider_metadata(provider_options),
      )
  }
}

///|
fn LanguageModelV4FileData::to_legacy_tool_content(
  self : LanguageModelV4FileData,
  media_type : String,
  filename : String,
  provider_options : Map[String, Json],
) -> LanguageModelToolResultContentPart {
  match self {
    V4FileData(data) =>
      LanguageModelToolFileData(
        data~,
        media_type~,
        filename~,
        provider_options~,
      )
    V4FileBytes(data) =>
      LanguageModelToolFileData(
        data=@base64.encode(data),
        media_type~,
        filename~,
        provider_options~,
      )
    V4FileUrl(url) =>
      LanguageModelToolFileUrl(url~, media_type~, filename~, provider_options~)
    V4FileReference(reference) =>
      LanguageModelToolFileReference(
        reference~,
        media_type~,
        filename~,
        provider_options~,
      )
    V4FileText(text) => LanguageModelToolText(text~, provider_options~)
  }
}

///|
fn LanguageModelV4ToolResultContentPart::to_legacy(
  self : LanguageModelV4ToolResultContentPart,
) -> LanguageModelToolResultContentPart {
  match self {
    V4ToolResultTextContent(text~, provider_options~) =>
      LanguageModelToolText(
        text~,
        provider_options=copy_provider_metadata(provider_options),
      )
    V4ToolResultFileContent(data~, media_type~, filename~, provider_options~) =>
      data.to_legacy_tool_content(
        media_type,
        filename.unwrap_or(""),
        copy_provider_metadata(provider_options),
      )
    V4ToolResultCustomContent(provider_options~) =>
      LanguageModelToolCustom(
        provider_options=copy_provider_metadata(provider_options),
      )
  }
}

///|
fn LanguageModelV4ToolResultOutput::from_legacy(
  output : LanguageModelToolResultOutput,
) -> LanguageModelV4ToolResultOutput {
  match output {
    LanguageModelToolTextOutput(value~, provider_options~) =>
      V4ToolResultTextOutput(
        value~,
        provider_options=copy_provider_metadata(provider_options),
      )
    LanguageModelToolJsonOutput(value~, provider_options~) =>
      V4ToolResultJsonOutput(
        value~,
        provider_options=copy_provider_metadata(provider_options),
      )
    LanguageModelToolExecutionDenied(reason~, provider_options~) =>
      V4ToolResultExecutionDenied(
        reason~,
        provider_options=copy_provider_metadata(provider_options),
      )
    LanguageModelToolErrorText(value~, provider_options~) =>
      V4ToolResultErrorText(
        value~,
        provider_options=copy_provider_metadata(provider_options),
      )
    LanguageModelToolErrorJson(value~, provider_options~) =>
      V4ToolResultErrorJson(
        value~,
        provider_options=copy_provider_metadata(provider_options),
      )
    LanguageModelToolContent(value~, provider_options~) =>
      V4ToolResultContentOutput(
        value=[
          for part in value => {
            LanguageModelV4ToolResultContentPart::from_legacy(part)
          }
        ],
        provider_options=copy_provider_metadata(provider_options),
      )
  }
}

///|
fn LanguageModelV4ToolResultOutput::to_legacy(
  self : LanguageModelV4ToolResultOutput,
) -> LanguageModelToolResultOutput {
  match self {
    V4ToolResultTextOutput(value~, provider_options~) =>
      LanguageModelToolTextOutput(
        value~,
        provider_options=copy_provider_metadata(provider_options),
      )
    V4ToolResultJsonOutput(value~, provider_options~) =>
      LanguageModelToolJsonOutput(
        value~,
        provider_options=copy_provider_metadata(provider_options),
      )
    V4ToolResultExecutionDenied(reason~, provider_options~) =>
      LanguageModelToolExecutionDenied(
        reason~,
        provider_options=copy_provider_metadata(provider_options),
      )
    V4ToolResultErrorText(value~, provider_options~) =>
      LanguageModelToolErrorText(
        value~,
        provider_options=copy_provider_metadata(provider_options),
      )
    V4ToolResultErrorJson(value~, provider_options~) =>
      LanguageModelToolErrorJson(
        value~,
        provider_options=copy_provider_metadata(provider_options),
      )
    V4ToolResultContentOutput(value~, provider_options~) =>
      LanguageModelToolContent(
        value=[ for part in value => part.to_legacy() ],
        provider_options=copy_provider_metadata(provider_options),
      )
  }
}

///|
fn LanguageModelV4ToolResultPart::from_legacy(
  result : LanguageModelToolResult,
) -> LanguageModelV4ToolResultPart {
  {
    tool_call_id: result.tool_call_id,
    tool_name: result.tool_name,
    output: LanguageModelV4ToolResultOutput::from_legacy(result.output),
    provider_options: copy_provider_metadata(result.provider_options),
  }
}

///|
fn LanguageModelV4ToolResultPart::to_legacy(
  self : LanguageModelV4ToolResultPart,
) -> LanguageModelToolResult {
  {
    tool_call_id: self.tool_call_id,
    tool_name: self.tool_name,
    output: self.output.to_legacy(),
    provider_options: copy_provider_metadata(self.provider_options),
  }
}

///|
fn LanguageModelV4ToolApprovalResponsePart::from_legacy(
  response : LanguageModelToolApprovalResponse,
) -> LanguageModelV4ToolApprovalResponsePart {
  LanguageModelV4ToolApprovalResponsePart::new(
    approval_id=response.approval_id,
    approved=response.approved,
    reason?=response.reason,
    provider_options=response.provider_options,
  )
}

///|
fn LanguageModelV4ToolApprovalResponsePart::to_legacy(
  self : LanguageModelV4ToolApprovalResponsePart,
) -> LanguageModelToolApprovalResponse {
  LanguageModelToolApprovalResponse::new(
    approval_id=self.approval_id,
    approved=self.approved,
    reason?=self.reason,
    provider_executed=true,
    provider_options=copy_provider_metadata(self.provider_options),
  )
}
