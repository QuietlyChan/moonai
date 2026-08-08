///|
fn model_file_part(
  file : @provider.LanguageModelV4File,
) -> @provider_utils.ModelContentPart {
  let part = match file.data {
    @provider.V4GeneratedFileBase64(data) =>
      @provider_utils.ModelContentPart::file_data(
        data~,
        media_type=file.media_type,
        filename="",
      )
    @provider.V4GeneratedFileBytes(data) =>
      @provider_utils.ModelContentPart::file_data(
        data=@base64.encode(data),
        media_type=file.media_type,
        filename="",
      )
    @provider.V4GeneratedFileUrl(url) =>
      @provider_utils.ModelContentPart::file_url(
        url~,
        media_type=file.media_type,
        filename="",
      )
  }
  part.with_provider_options(file.provider_metadata)
}

///|
fn model_reasoning_file_part(
  file : @provider.LanguageModelV4ReasoningFile,
) -> @provider_utils.ModelContentPart {
  let part = match file.data {
    @provider.V4GeneratedFileBase64(data) =>
      @provider_utils.ModelContentPart::reasoning_file_data(
        data~,
        media_type=file.media_type,
      )
    @provider.V4GeneratedFileBytes(data) =>
      @provider_utils.ModelContentPart::reasoning_file_data(
        data=@base64.encode(data),
        media_type=file.media_type,
      )
    @provider.V4GeneratedFileUrl(url) =>
      @provider_utils.ModelContentPart::reasoning_file_url(
        url~,
        media_type=file.media_type,
      )
  }
  part.with_provider_options(file.provider_metadata)
}

///|
async fn model_tool_result(
  result : GenerateTextToolResult,
  provider_executed : Bool,
  tools : @provider_utils.ToolSet,
) -> @provider_utils.ModelToolResult {
  let output = if result.is_error {
    if provider_executed {
      @provider_utils.ModelToolResultOutput::error_json(result.output)
    } else {
      match result.output {
        String(value) =>
          @provider_utils.ModelToolResultOutput::error_text(value)
        value => @provider_utils.ModelToolResultOutput::error_json(value)
      }
    }
  } else {
    match tools.get(result.tool_name) {
      Some(tool) =>
        tool.to_model_output(
          @provider_utils.ToolModelOutputOptions::new(
            tool_call_id=result.tool_call_id,
            input=result.input,
            output=result.output,
          ),
        )
      None =>
        match result.output {
          String(value) => @provider_utils.ModelToolResultOutput::text(value)
          value => @provider_utils.ModelToolResultOutput::json(value)
        }
    }
  }
  {
    tool_call_id: result.tool_call_id,
    tool_name: result.tool_name,
    output,
    provider_options: @provider.copy_provider_metadata(result.provider_metadata),
  }
}

///|
async fn assistant_response_parts(
  content : Array[GenerateTextContent],
  tools : @provider_utils.ToolSet,
) -> Array[@provider_utils.ModelContentPart] {
  let parts : Array[@provider_utils.ModelContentPart] = []
  for item in content {
    match item {
      GenerateTextText(value) =>
        if !value.text.is_empty() {
          parts.push(
            @provider_utils.ModelContentPart::text(value.text).with_provider_options(
              value.provider_metadata,
            ),
          )
        }
      GenerateTextReasoning(value) =>
        parts.push(
          @provider_utils.ModelContentPart::reasoning(value.text).with_provider_options(
            value.provider_metadata,
          ),
        )
      GenerateTextCustom(value) =>
        parts.push(
          @provider_utils.ModelContentPart::custom(value.kind).with_provider_options(
            value.provider_metadata,
          ),
        )
      GenerateTextReasoningFile(value) =>
        parts.push(model_reasoning_file_part(value))
      GenerateTextFile(value) => parts.push(model_file_part(value))
      GenerateTextToolApprovalRequest(value) => {
        let signature = value.signature
        parts.push(
          @provider_utils.ModelContentPart::tool_approval_request(
            @provider_utils.ModelToolApprovalRequest::new(
              approval_id=value.approval_id,
              tool_call_id=value.tool_call.tool_call_id,
              is_automatic=value.is_automatic,
              signature?,
            ),
          ).with_provider_options(value.provider_metadata),
        )
      }
      GenerateTextToolApprovalResponse(_) => ()
      GenerateTextSource(_) => ()
      GenerateTextToolCall(value) =>
        parts.push(
          @provider_utils.ModelContentPart::tool_call(
            @provider_utils.ModelToolCall::new(
              id=value.tool_call_id,
              name=value.tool_name,
              input=value.input,
              provider_executed=value.provider_executed,
              dynamic=value.dynamic,
              provider_options=value.provider_metadata,
            ),
          ),
        )
      GenerateTextToolResult(value) =>
        if value.provider_executed {
          parts.push(
            @provider_utils.ModelContentPart::tool_result(
              model_tool_result(value, true, tools),
            ),
          )
        }
    }
  }
  parts
}

///|
async fn append_client_result_part(
  parts : Array[@provider_utils.ModelContentPart],
  result : GenerateTextToolResult,
  tools : @provider_utils.ToolSet,
) -> Unit {
  parts.push(
    @provider_utils.ModelContentPart::tool_result(
      model_tool_result(result, false, tools),
    ),
  )
}

///|
async fn client_tool_result_parts(
  content : Array[GenerateTextContent],
  tools : @provider_utils.ToolSet,
) -> Array[@provider_utils.ModelContentPart] {
  let parts : Array[@provider_utils.ModelContentPart] = []
  let included : Map[String, Bool] = Map([])
  for item in content {
    match item {
      GenerateTextToolApprovalResponse(response) => {
        let reason = response.reason
        parts.push(
          @provider_utils.ModelContentPart::tool_approval_response(
            @provider_utils.ModelToolApprovalResponse::new(
              approval_id=response.approval_id,
              approved=response.approved,
              reason?,
              provider_executed=response.provider_executed,
            ),
          ),
        )
        if !response.approved {
          let provider_options : Map[String, Json] = if response.provider_executed {
            Map([("openai", { "approvalId": response.approval_id })])
          } else {
            Map([])
          }
          parts.push(
            @provider_utils.ModelContentPart::tool_result(
              @provider_utils.ModelToolResult::execution_denied(
                tool_call_id=response.tool_call.tool_call_id,
                tool_name=response.tool_call.tool_name,
                reason?,
                provider_options~,
              ),
            ),
          )
          included[response.tool_call.tool_call_id] = true
        }
      }
      _ => ()
    }
  }
  for item in content {
    match item {
      GenerateTextToolCall(call) if !call.provider_executed =>
        for candidate in content {
          match candidate {
            GenerateTextToolResult(result) =>
              if !result.provider_executed &&
                result.tool_call_id == call.tool_call_id {
                append_client_result_part(parts, result, tools)
                included[result.tool_call_id] = true
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  for item in content {
    match item {
      GenerateTextToolResult(result) =>
        if !result.provider_executed &&
          included.get(result.tool_call_id) is None {
          append_client_result_part(parts, result, tools)
          included[result.tool_call_id] = true
        }
      _ => ()
    }
  }
  parts
}

///|
async fn to_response_messages(
  content : Array[GenerateTextContent],
  tools : @provider_utils.ToolSet,
) -> Array[@provider_utils.ModelMessage] {
  let messages : Array[@provider_utils.ModelMessage] = []
  let assistant_parts = assistant_response_parts(content, tools)
  if assistant_parts.length() > 0 {
    messages.push(
      @provider_utils.ModelMessage::assistant_parts(assistant_parts),
    )
  }
  let tool_parts = client_tool_result_parts(content, tools)
  if tool_parts.length() > 0 {
    messages.push(@provider_utils.ModelMessage::tool_content(tool_parts))
  }
  messages
}
