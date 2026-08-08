///|
async fn resolve_tool_approval(
  tools : @provider_utils.ToolSet,
  tool_call : GenerateTextToolCall,
  tool_approval : ToolApprovalConfiguration?,
  messages : Array[@provider_utils.ModelMessage],
  tools_context : Map[String, Json],
  runtime_context : Json,
) -> ToolApprovalStatus {
  match tool_approval {
    Some(ToolApprovalGeneric(resolve)) =>
      return resolve({
        tool_call,
        tools: @provider_utils.copy_tool_set(tools),
        tools_context: @provider.copy_provider_metadata(tools_context),
        runtime_context,
        messages: copy_model_messages(messages),
      })
    Some(ToolApprovalPerTool(rules)) =>
      match rules.get(tool_call.tool_name) {
        Some(ToolApprovalRuleStatus(status)) => return status
        Some(ToolApprovalRuleFunction(resolve)) =>
          return resolve(tool_call.input, {
            tool_call_id: tool_call.tool_call_id,
            messages: copy_model_messages(messages),
            tool_context: tools_context
            .get(tool_call.tool_name)
            .unwrap_or(Json::empty_object()),
            runtime_context,
          })
        None => ()
      }
    None => ()
  }
  match tools.get(tool_call.tool_name) {
    Some(tool) =>
      match
        tool.resolve_needs_approval(
          tool_call.input,
          @provider_utils.ToolNeedsApprovalOptions::new(
            tool_call_id=tool_call.tool_call_id,
            messages~,
            context=tools_context
              .get(tool_call.tool_name)
              .unwrap_or(Json::empty_object()),
          ),
        ) {
        Some(true) => ToolApprovalUserApproval
        Some(false) | None => ToolApprovalNotApplicable
      }
    None => ToolApprovalNotApplicable
  }
}

///|
priv struct ResolvedStepToolApprovals {
  requests : Array[GenerateTextToolApprovalRequestOutput]
  responses : Array[GenerateTextToolApprovalResponseOutput]
  blocked_tool_call_ids : Map[String, Bool]
  denied_client_count : Int
  provider_response_count : Int
}

///|
async fn resolve_step_tool_approvals(
  calls : Array[GenerateTextToolCall],
  tools : @provider_utils.ToolSet,
  tool_approval : ToolApprovalConfiguration?,
  tool_approval_secret : ToolApprovalSecret?,
  messages : Array[@provider_utils.ModelMessage],
  tools_context : Map[String, Json],
  runtime_context : Json,
) -> ResolvedStepToolApprovals {
  let requests : Array[GenerateTextToolApprovalRequestOutput] = []
  let responses : Array[GenerateTextToolApprovalResponseOutput] = []
  let blocked_tool_call_ids : Map[String, Bool] = Map([])
  let mut denied_client_count = 0
  let mut provider_response_count = 0
  for call in calls {
    guard !call.invalid && tools.get(call.tool_name) is Some(_) else {
      continue
    }
    let status = resolve_tool_approval(
      tools, call, tool_approval, messages, tools_context, runtime_context,
    )
    guard status != ToolApprovalNotApplicable else { continue }
    let approval_id = @provider_utils.generate_id()
    let is_automatic = status is ToolApprovalApproved(_) ||
      status is ToolApprovalDenied(_)
    requests.push({
      approval_id,
      tool_call: call,
      is_automatic,
      signature: maybe_sign_tool_approval(
        tool_approval_secret,
        approval_id,
        call.tool_call_id,
        call.tool_name,
        call.input,
      ),
      provider_metadata: Map([]),
    })
    match status {
      ToolApprovalUserApproval =>
        blocked_tool_call_ids[call.tool_call_id] = true
      ToolApprovalApproved(reason~) => {
        responses.push({
          approval_id,
          tool_call: call,
          approved: true,
          reason,
          provider_executed: call.provider_executed,
        })
        if call.provider_executed {
          provider_response_count = provider_response_count + 1
        }
      }
      ToolApprovalDenied(reason~) => {
        responses.push({
          approval_id,
          tool_call: call,
          approved: false,
          reason,
          provider_executed: call.provider_executed,
        })
        blocked_tool_call_ids[call.tool_call_id] = true
        if call.provider_executed {
          provider_response_count = provider_response_count + 1
        } else {
          denied_client_count = denied_client_count + 1
        }
      }
      ToolApprovalNotApplicable => ()
    }
  }
  {
    requests,
    responses,
    blocked_tool_call_ids,
    denied_client_count,
    provider_response_count,
  }
}

///|
fn append_tool_approvals(
  content : Array[GenerateTextContent],
  approvals : ResolvedStepToolApprovals,
) -> Array[GenerateTextContent] {
  let combined = content.copy()
  for request in approvals.requests {
    combined.push(GenerateTextToolApprovalRequest(request))
  }
  for response in approvals.responses {
    combined.push(GenerateTextToolApprovalResponse(response))
  }
  combined
}

///|
fn tool_approval_requests_from_content(
  content : Array[GenerateTextContent],
) -> Array[GenerateTextToolApprovalRequestOutput] {
  let values : Array[GenerateTextToolApprovalRequestOutput] = []
  for part in content {
    match part {
      GenerateTextToolApprovalRequest(value) => values.push(value)
      _ => ()
    }
  }
  values
}

///|
fn tool_approval_responses_from_content(
  content : Array[GenerateTextContent],
) -> Array[GenerateTextToolApprovalResponseOutput] {
  let values : Array[GenerateTextToolApprovalResponseOutput] = []
  for part in content {
    match part {
      GenerateTextToolApprovalResponse(value) => values.push(value)
      _ => ()
    }
  }
  values
}
