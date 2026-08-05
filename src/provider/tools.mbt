///|
/// A tool advertised to a language model.
///
/// Function tools are executed by the caller. Provider tools use a stable
/// `<provider>.<tool>` identifier and can be executed by the provider.
pub(all) enum ToolDefinition {
  FunctionTool(
    name~ : String,
    description~ : String?,
    input_schema~ : Json,
    input_examples~ : Array[Json],
    strict~ : Bool?,
    provider_options~ : Map[String, Json]
  )
  ProviderTool(id~ : String, name~ : String, args~ : Json)
} derive(Debug)

///|
/// Construct a function tool definition.
pub fn ToolDefinition::new(
  name : String,
  parameters : Json,
  description? : String,
  input_examples? : Array[Json] = [],
  strict? : Bool,
  provider_options? : Map[String, Json] = Map([]),
) -> ToolDefinition {
  FunctionTool(
    name~,
    description~,
    input_schema=parameters,
    input_examples~,
    strict~,
    provider_options~,
  )
}

///|
/// Construct a provider-defined tool.
pub fn ToolDefinition::provider(
  id~ : String,
  name~ : String,
  args? : Json = Json::empty_object(),
) -> ToolDefinition {
  ProviderTool(id~, name~, args~)
}

///|
/// Return the name visible to the model.
pub fn ToolDefinition::name(self : ToolDefinition) -> String {
  match self {
    FunctionTool(name~, ..) | ProviderTool(name~, ..) => name
  }
}

///|
/// Return whether a function tool requests strict schema generation.
pub fn ToolDefinition::strict(self : ToolDefinition) -> Bool {
  match self {
    FunctionTool(strict~, ..) => strict.unwrap_or(false)
    ProviderTool(..) => false
  }
}

///|
/// Return the optional strict-mode setting without applying a default.
pub fn ToolDefinition::strict_setting(self : ToolDefinition) -> Bool? {
  match self {
    FunctionTool(strict~, ..) => strict
    ProviderTool(..) => None
  }
}

///|
/// Return the optional function-tool description.
pub fn ToolDefinition::description(self : ToolDefinition) -> String? {
  match self {
    FunctionTool(description~, ..) => description
    ProviderTool(..) => None
  }
}

///|
/// One complete model-generated tool call.
pub(all) struct ToolCall {
  id : String
  name : String
  arguments : String
  provider_executed : Bool
  dynamic : Bool
  provider_metadata : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a complete tool call.
pub fn ToolCall::new(
  id~ : String,
  name~ : String,
  arguments~ : String,
  provider_executed? : Bool = false,
  dynamic? : Bool = false,
  provider_metadata? : Map[String, Json] = Map([]),
) -> ToolCall {
  { id, name, arguments, provider_executed, dynamic, provider_metadata }
}

///|
/// A result produced by a provider-executed tool.
pub(all) struct ToolResult {
  tool_call_id : String
  tool_name : String
  result : Json
  is_error : Bool
  preliminary : Bool
  dynamic : Bool
  provider_metadata : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a provider-executed tool result.
pub fn ToolResult::new(
  tool_call_id~ : String,
  tool_name~ : String,
  result~ : Json,
  is_error? : Bool = false,
  preliminary? : Bool = false,
  dynamic? : Bool = false,
  provider_metadata? : Map[String, Json] = Map([]),
) -> ToolResult {
  {
    tool_call_id,
    tool_name,
    result,
    is_error,
    preliminary,
    dynamic,
    provider_metadata,
  }
}

///|
/// An approval request for a provider-executed tool call.
pub(all) struct ToolApprovalRequest {
  approval_id : String
  tool_call_id : String
  provider_metadata : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a provider tool approval request.
pub fn ToolApprovalRequest::new(
  approval_id~ : String,
  tool_call_id~ : String,
  provider_metadata? : Map[String, Json] = Map([]),
) -> ToolApprovalRequest {
  { approval_id, tool_call_id, provider_metadata }
}

///|
/// Content embedded in a provider-facing tool result output.
pub(all) enum LanguageModelToolResultContentPart {
  LanguageModelToolText(text~ : String, provider_options~ : Map[String, Json])
  LanguageModelToolFileUrl(
    url~ : String,
    media_type~ : String,
    filename~ : String,
    provider_options~ : Map[String, Json]
  )
  LanguageModelToolFileData(
    data~ : String,
    media_type~ : String,
    filename~ : String,
    provider_options~ : Map[String, Json]
  )
  LanguageModelToolFileReference(
    reference~ : ProviderReference,
    media_type~ : String,
    filename~ : String,
    provider_options~ : Map[String, Json]
  )
  LanguageModelToolCustom(provider_options~ : Map[String, Json])
} derive(Debug, Eq)

///|
/// Standardized output shape of a provider-facing tool result.
pub(all) enum LanguageModelToolResultOutput {
  LanguageModelToolTextOutput(
    value~ : String,
    provider_options~ : Map[String, Json]
  )
  LanguageModelToolJsonOutput(
    value~ : Json,
    provider_options~ : Map[String, Json]
  )
  LanguageModelToolExecutionDenied(
    reason~ : String?,
    provider_options~ : Map[String, Json]
  )
  LanguageModelToolErrorText(
    value~ : String,
    provider_options~ : Map[String, Json]
  )
  LanguageModelToolErrorJson(
    value~ : Json,
    provider_options~ : Map[String, Json]
  )
  LanguageModelToolContent(
    value~ : Array[LanguageModelToolResultContentPart],
    provider_options~ : Map[String, Json]
  )
} derive(Debug, Eq)

///|
/// A tool result carried in a provider-facing prompt.
pub(all) struct LanguageModelToolResult {
  tool_call_id : String
  tool_name : String
  output : LanguageModelToolResultOutput
  provider_options : Map[String, Json]
} derive(Debug, Eq)

///|
/// A provider-executed tool approval request carried in assistant history.
pub(all) struct LanguageModelToolApprovalRequest {
  approval_id : String
  tool_call_id : String
  is_automatic : Bool
  signature : String?
} derive(Debug, Eq)

///|
/// A tool approval response carried in a provider-facing prompt.
pub(all) struct LanguageModelToolApprovalResponse {
  approval_id : String
  approved : Bool
  reason : String?
  provider_executed : Bool
  provider_options : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a provider-facing text tool result.
pub fn LanguageModelToolResult::text(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelToolResult {
  {
    tool_call_id,
    tool_name,
    output: LanguageModelToolTextOutput(
      value~,
      provider_options=copy_provider_metadata(provider_options),
    ),
    provider_options: copy_provider_metadata(provider_options),
  }
}

///|
/// Construct a provider-facing JSON tool result.
pub fn LanguageModelToolResult::json(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : Json,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelToolResult {
  {
    tool_call_id,
    tool_name,
    output: LanguageModelToolJsonOutput(
      value~,
      provider_options=copy_provider_metadata(provider_options),
    ),
    provider_options: copy_provider_metadata(provider_options),
  }
}

///|
/// Construct a provider-facing execution-denied tool result.
pub fn LanguageModelToolResult::execution_denied(
  tool_call_id~ : String,
  tool_name~ : String,
  reason? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelToolResult {
  {
    tool_call_id,
    tool_name,
    output: LanguageModelToolExecutionDenied(
      reason~,
      provider_options=copy_provider_metadata(provider_options),
    ),
    provider_options: copy_provider_metadata(provider_options),
  }
}

///|
/// Construct a multimodal provider-facing tool result.
pub fn LanguageModelToolResult::content(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : Array[LanguageModelToolResultContentPart],
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelToolResult {
  {
    tool_call_id,
    tool_name,
    output: LanguageModelToolContent(
      value~,
      provider_options=copy_provider_metadata(provider_options),
    ),
    provider_options: copy_provider_metadata(provider_options),
  }
}

///|
/// Construct an error-text provider-facing tool result.
pub fn LanguageModelToolResult::error_text(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : String,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelToolResult {
  {
    tool_call_id,
    tool_name,
    output: LanguageModelToolErrorText(
      value~,
      provider_options=copy_provider_metadata(provider_options),
    ),
    provider_options: copy_provider_metadata(provider_options),
  }
}

///|
/// Construct an error-JSON provider-facing tool result.
pub fn LanguageModelToolResult::error_json(
  tool_call_id~ : String,
  tool_name~ : String,
  value~ : Json,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelToolResult {
  {
    tool_call_id,
    tool_name,
    output: LanguageModelToolErrorJson(
      value~,
      provider_options=copy_provider_metadata(provider_options),
    ),
    provider_options: copy_provider_metadata(provider_options),
  }
}

///|
/// Construct a provider-facing tool approval response.
pub fn LanguageModelToolApprovalResponse::new(
  approval_id~ : String,
  approved~ : Bool,
  reason? : String,
  provider_executed? : Bool = false,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelToolApprovalResponse {
  {
    approval_id,
    approved,
    reason,
    provider_executed,
    provider_options: copy_provider_metadata(provider_options),
  }
}

///|
/// Convert one tool-result content part to a provider-neutral JSON value.
pub fn LanguageModelToolResultContentPart::to_json(
  self : LanguageModelToolResultContentPart,
) -> Json {
  match self {
    LanguageModelToolText(text~, ..) =>
      Json::object(
        Map([("type", Json::string("text")), ("text", Json::string(text))]),
      )
    LanguageModelToolFileUrl(url~, media_type~, filename~, ..) => {
      let fields : Map[String, Json] = Map(
        [
          ("type", Json::string("file")),
          ("url", Json::string(url)),
          ("mediaType", Json::string(media_type)),
          ..if filename != "" {
            [("filename", Json::string(filename))]
          },
        ],
      )
      Json::object(fields)
    }
    LanguageModelToolFileData(data~, media_type~, filename~, ..) => {
      let fields : Map[String, Json] = Map(
        [
          ("type", Json::string("file")),
          ("data", Json::string(data)),
          ("mediaType", Json::string(media_type)),
          ..if filename != "" {
            [("filename", Json::string(filename))]
          },
        ],
      )
      Json::object(fields)
    }
    LanguageModelToolFileReference(reference~, media_type~, filename~, ..) => {
      let reference_fields : Map[String, Json] = Map([])
      for entry in reference.providers() {
        reference_fields[entry] = Json::string(
          reference.get(entry).unwrap_or(""),
        )
      }
      let fields : Map[String, Json] = Map(
        [
          ("type", Json::string("file")),
          ("reference", Json::object(reference_fields)),
          ("mediaType", Json::string(media_type)),
          ..if filename != "" {
            [("filename", Json::string(filename))]
          },
        ],
      )
      Json::object(fields)
    }
    LanguageModelToolCustom(..) =>
      Json::object(Map([("type", Json::string("custom"))]))
  }
}

///|
/// Convert a tool-result output to a provider-neutral JSON value.
pub fn LanguageModelToolResultOutput::to_json(
  self : LanguageModelToolResultOutput,
) -> Json {
  match self {
    LanguageModelToolTextOutput(value~, ..) => Json::string(value)
    LanguageModelToolJsonOutput(value~, ..) => value
    LanguageModelToolExecutionDenied(reason~, ..) =>
      Json::object(
        Map(
          [
            ("type", Json::string("execution-denied")),
            ..if reason is Some(value) {
              [("reason", Json::string(value))]
            },
          ],
        ),
      )
    LanguageModelToolErrorText(value~, ..) =>
      Json::object(
        Map([
          ("type", Json::string("error-text")),
          ("value", Json::string(value)),
        ]),
      )
    LanguageModelToolErrorJson(value~, ..) =>
      Json::object(
        Map([("type", Json::string("error-json")), ("value", value)]),
      )
    LanguageModelToolContent(value~, ..) =>
      Json::array([ for part in value => part.to_json() ])
  }
}

///|
/// Return the serialized output of a provider-facing tool result.
pub fn LanguageModelToolResult::output_json(
  self : LanguageModelToolResult,
) -> Json {
  self.output.to_json()
}
