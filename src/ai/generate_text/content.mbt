///|
fn find_tool_call(
  calls : Array[GenerateTextToolCall],
  tool_call_id : String,
) -> GenerateTextToolCall? {
  for call in calls {
    if call.tool_call_id == tool_call_id {
      return Some(call)
    }
  }
  None
}

///|
fn copy_v4_source(
  source : @provider.LanguageModelV4Source,
) -> @provider.LanguageModelV4Source {
  match source {
    @provider.V4UrlSource(id~, url~, title~, provider_metadata~) =>
      @provider.V4UrlSource(
        id~,
        url~,
        title~,
        provider_metadata=@provider.copy_provider_metadata(provider_metadata),
      )
    @provider.V4DocumentSource(
      id~,
      media_type~,
      title~,
      filename~,
      provider_metadata~
    ) =>
      @provider.V4DocumentSource(
        id~,
        media_type~,
        title~,
        filename~,
        provider_metadata=@provider.copy_provider_metadata(provider_metadata),
      )
  }
}

///|
fn normalize_provider_content(
  content : Array[@provider.LanguageModelV4Content],
  tool_calls : Array[GenerateTextToolCall],
) -> Array[GenerateTextContent] {
  let normalized : Array[GenerateTextContent] = []
  for part in content {
    match part {
      @provider.V4TextOutput(value) =>
        normalized.push(
          GenerateTextText({
            text: value.text,
            provider_metadata: @provider.copy_provider_metadata(
              value.provider_metadata,
            ),
          }),
        )
      @provider.V4ReasoningOutput(value) =>
        normalized.push(
          GenerateTextReasoning({
            text: value.text,
            provider_metadata: @provider.copy_provider_metadata(
              value.provider_metadata,
            ),
          }),
        )
      @provider.V4CustomOutput(value) =>
        normalized.push(
          GenerateTextCustom({
            kind: value.kind,
            provider_metadata: @provider.copy_provider_metadata(
              value.provider_metadata,
            ),
          }),
        )
      @provider.V4ReasoningFileOutput(value) =>
        normalized.push(
          GenerateTextReasoningFile({
            media_type: value.media_type,
            data: value.data,
            provider_metadata: @provider.copy_provider_metadata(
              value.provider_metadata,
            ),
          }),
        )
      @provider.V4FileOutput(value) =>
        normalized.push(
          GenerateTextFile({
            media_type: value.media_type,
            data: value.data,
            provider_metadata: @provider.copy_provider_metadata(
              value.provider_metadata,
            ),
          }),
        )
      @provider.V4ToolApprovalRequestOutput(value) =>
        match find_tool_call(tool_calls, value.tool_call_id) {
          Some(tool_call) =>
            normalized.push(
              GenerateTextToolApprovalRequest({
                approval_id: value.approval_id,
                tool_call,
                is_automatic: false,
                signature: None,
                provider_metadata: @provider.copy_provider_metadata(
                  value.provider_metadata,
                ),
              }),
            )
          None => ()
        }
      @provider.V4SourceOutput(value) =>
        normalized.push(GenerateTextSource(copy_v4_source(value)))
      @provider.V4ToolCallOutput(value) =>
        match find_tool_call(tool_calls, value.tool_call_id) {
          Some(call) => normalized.push(GenerateTextToolCall(call))
          None => ()
        }
      @provider.V4ToolResultOutput(value) => {
        let matching_call = find_tool_call(tool_calls, value.tool_call_id)
        normalized.push(
          GenerateTextToolResult({
            tool_call_id: value.tool_call_id,
            tool_name: value.tool_name,
            input: match matching_call {
              Some(call) => call.input
              None => Json::null()
            },
            output: value.result,
            is_error: value.is_error,
            preliminary: value.preliminary,
            provider_executed: true,
            dynamic: match matching_call {
              Some(call) => call.dynamic
              None => value.dynamic
            },
            provider_metadata: @provider.copy_provider_metadata(
              value.provider_metadata,
            ),
          }),
        )
      }
    }
  }
  normalized
}

///|
fn append_client_tool_results(
  content : Array[GenerateTextContent],
  results : Array[GenerateTextToolResult],
) -> Array[GenerateTextContent] {
  let combined = content.copy()
  for result in results {
    combined.push(GenerateTextToolResult(result))
  }
  combined
}
