///|
priv struct CollectedToolApproval {
  request : @provider_utils.ModelToolApprovalRequest
  response : @provider_utils.ModelToolApprovalResponse
  tool_call : GenerateTextToolCall
}

///|
priv struct CollectedToolApprovals {
  approved : Array[CollectedToolApproval]
  denied : Array[CollectedToolApproval]
}

///|
fn generate_text_call_from_model_call(
  call : @provider_utils.ModelToolCall,
) -> GenerateTextToolCall {
  {
    tool_call_id: call.id,
    tool_name: call.name,
    input: call.input,
    input_text: call.input.stringify(),
    provider_executed: call.provider_executed,
    dynamic: call.dynamic,
    invalid: false,
    error: None,
    provider_metadata: @provider.copy_provider_metadata(call.provider_options),
  }
}

///|
fn collect_tool_approvals(
  messages : Array[@provider_utils.ModelMessage],
) -> CollectedToolApprovals raise {
  guard messages.length() > 0 &&
    messages[messages.length() - 1].role is @provider_utils.ModelTool(_) else {
    return { approved: [], denied: [] }
  }
  let calls : Map[String, GenerateTextToolCall] = Map([])
  let requests : Map[String, @provider_utils.ModelToolApprovalRequest] = Map([])
  for message in messages {
    guard message.role is @provider_utils.ModelAssistant else { continue }
    for call in message.tool_calls {
      calls[call.id] = generate_text_call_from_model_call(call)
    }
    for wrapped_part in message.parts {
      match wrapped_part.without_provider_options() {
        @provider_utils.ModelToolCallPart(call~) =>
          calls[call.id] = generate_text_call_from_model_call(call)
        @provider_utils.ModelToolApprovalRequestPart(request~) =>
          requests[request.approval_id] = request
        _ => ()
      }
    }
  }
  let last_message = messages[messages.length() - 1]
  let existing_results : Map[String, Bool] = Map([])
  for wrapped_part in last_message.parts {
    match wrapped_part.without_provider_options() {
      @provider_utils.ModelToolResultPart(result~) =>
        existing_results[result.tool_call_id] = true
      _ => ()
    }
  }
  let approved : Array[CollectedToolApproval] = []
  let denied : Array[CollectedToolApproval] = []
  for wrapped_part in last_message.parts {
    guard wrapped_part.without_provider_options()
      is @provider_utils.ModelToolApprovalResponsePart(response~) else {
      continue
    }
    guard requests.get(response.approval_id) is Some(request) else {
      raise InvalidToolApprovalError(approval_id=response.approval_id)
    }
    guard existing_results.get(request.tool_call_id) is None else { continue }
    guard calls.get(request.tool_call_id) is Some(tool_call) else {
      raise ToolCallNotFoundForApprovalError(
        tool_call_id=request.tool_call_id,
        approval_id=request.approval_id,
      )
    }
    let value = { request, response, tool_call }
    if response.approved {
      approved.push(value)
    } else {
      denied.push(value)
    }
  }
  { approved, denied }
}

///|
async fn initial_tool_approval_result_messages(
  messages : Array[@provider_utils.ModelMessage],
  tools : @provider_utils.ToolSet,
  tool_approval : ToolApprovalConfiguration?,
  tool_approval_secret : ToolApprovalSecret?,
  tools_context : Map[String, Json],
  runtime_context : Json,
  cancellation_token : @provider.CancellationToken?,
  experimental_sandbox : @provider_utils.SandboxSession?,
) -> Array[@provider_utils.ModelMessage] {
  let collected = collect_tool_approvals(messages)
  let parts : Array[@provider_utils.ModelContentPart] = []
  let denied = collected.denied.copy()
  for approval in collected.approved {
    validate_tool_approval_signature(
      tool_approval_secret,
      approval.request,
      approval.tool_call,
    )
    guard !approval.tool_call.provider_executed else { continue }
    guard tools.get(approval.tool_call.tool_name) is Some(tool) else {
      continue
    }
    match tool.input_schema() {
      Some(schema) if !@provider_utils.json_schema_matches(
          schema,
          approval.tool_call.input,
        ) =>
        raise InvalidToolInputError(
          tool_call_id=approval.tool_call.tool_call_id,
          tool_name=approval.tool_call.tool_name,
          input=approval.tool_call.input.stringify(),
          message="The approved tool input no longer matches its schema.",
        )
      _ => ()
    }
    let status = resolve_tool_approval(
      tools,
      approval.tool_call,
      tool_approval,
      messages,
      tools_context,
      runtime_context,
    )
    match status {
      ToolApprovalDenied(reason~) => {
        let response = {
          ..approval.response,
          approved: false,
          reason: match reason {
            Some(_) => reason
            None => approval.response.reason
          },
        }
        denied.push({ ..approval, response, })
        continue
      }
      _ => ()
    }
    guard tool.is_executable() else { continue }
    let outcome = execute_tool_call(
      approval.tool_call,
      tool,
      messages,
      tools_context
      .get(approval.tool_call.tool_name)
      .unwrap_or(Json::empty_object()),
      cancellation_token,
      experimental_sandbox,
    )
    parts.push(
      @provider_utils.ModelContentPart::tool_result(
        model_tool_result(outcome.result, false, tools),
      ),
    )
  }
  for approval in denied {
    guard !approval.tool_call.provider_executed else { continue }
    let reason = approval.response.reason
    parts.push(
      @provider_utils.ModelContentPart::tool_result(
        @provider_utils.ModelToolResult::execution_denied(
          tool_call_id=approval.tool_call.tool_call_id,
          tool_name=approval.tool_call.tool_name,
          reason?,
        ),
      ),
    )
  }
  if parts.length() == 0 {
    []
  } else {
    [@provider_utils.ModelMessage::tool_content(parts)]
  }
}
