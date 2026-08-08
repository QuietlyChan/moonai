///|
/// Return whether a model tool message contains only provider-facing
/// structured parts. Plain text tool messages carry their call id in the
/// message role and must stay separate when consecutive messages are merged.
fn structured_tool_message(message : @provider_utils.ModelMessage) -> Bool {
  match message.role {
    @provider_utils.ModelTool(_) if message.content == "" &&
      message.parts.length() > 0 => {
      for part in message.parts {
        match part.without_provider_options() {
          @provider_utils.ModelToolResultPart(_)
          | @provider_utils.ModelToolApprovalResponsePart(_) => ()
          _ => return false
        }
      }
      true
    }
    _ => false
  }
}

///|
/// Remove content that is meaningful only to the client-side approval flow.
fn normalize_model_message(
  message : @provider_utils.ModelMessage,
) -> @provider_utils.ModelMessage {
  match message.role {
    @provider_utils.ModelAssistant => {
      let parts : Array[@provider_utils.ModelContentPart] = []
      for part in message.parts {
        match part.without_provider_options() {
          @provider_utils.ModelText(value) if value == "" &&
            part.provider_options().length() == 0 => ()
          @provider_utils.ModelToolApprovalRequestPart(_) => ()
          _ => parts.push(part)
        }
      }
      message.with_parts(parts)
    }
    @provider_utils.ModelUser => {
      let parts : Array[@provider_utils.ModelContentPart] = []
      for part in message.parts {
        match part.without_provider_options() {
          @provider_utils.ModelText(value) if value == "" => ()
          _ => parts.push(part)
        }
      }
      message.with_parts(parts)
    }
    @provider_utils.ModelTool(_) => {
      let parts : Array[@provider_utils.ModelContentPart] = []
      for part in message.parts {
        match part.without_provider_options() {
          @provider_utils.ModelToolApprovalResponsePart(response~) if !response.provider_executed =>
            ()
          _ => parts.push(part)
        }
      }
      message.with_parts(parts)
    }
    @provider_utils.ModelSystem => message.copy()
  }
}

///|
/// Merge adjacent structured tool messages in the same way as the AI SDK's
/// V4 prompt conversion. Each structured result keeps its own tool-call id.
fn merge_structured_tool_messages(
  messages : Array[@provider_utils.ModelMessage],
) -> Array[@provider_utils.ModelMessage] {
  let result : Array[@provider_utils.ModelMessage] = []
  for message in messages {
    guard structured_tool_message(message) && result.length() > 0 else {
      result.push(message)
      continue
    }
    let previous_index = result.length() - 1
    guard structured_tool_message(result[previous_index]) else {
      result.push(message)
      continue
    }
    let previous = result[previous_index]
    let merged_parts = previous.parts.copy()
    for part in message.parts {
      merged_parts.push(part)
    }
    result[previous_index] = previous
      .with_parts(merged_parts)
      .with_provider_options(message.provider_options)
  }
  result
}

///|
/// Add a client-executed tool call to the pending set once.
fn add_pending_tool_call(
  call : @provider_utils.ModelToolCall,
  pending : Map[String, Bool],
  order : Array[String],
) -> Unit {
  guard !call.provider_executed && call.id != "" else { return }
  if pending.get(call.id) is None {
    order.push(call.id)
  }
  pending[call.id] = true
}

///|
/// Collect approval responses before filtering them, because an approval is a
/// valid completion of its associated client-side tool call.
fn approved_tool_call_ids(
  messages : Array[@provider_utils.ModelMessage],
) -> Map[String, Bool] {
  let approval_to_tool_call : Map[String, String] = Map([])
  for message in messages {
    if message.role is @provider_utils.ModelAssistant {
      for part in message.parts {
        match part.without_provider_options() {
          @provider_utils.ModelToolApprovalRequestPart(request~) =>
            approval_to_tool_call[request.approval_id] = request.tool_call_id
          _ => ()
        }
      }
    }
  }
  let approved : Map[String, Bool] = Map([])
  for message in messages {
    if message.role is @provider_utils.ModelTool(_) {
      for part in message.parts {
        match part.without_provider_options() {
          @provider_utils.ModelToolApprovalResponsePart(response~) =>
            match approval_to_tool_call.get(response.approval_id) {
              Some(tool_call_id) => approved[tool_call_id] = true
              None => ()
            }
          _ => ()
        }
      }
    }
  }
  approved
}

///|
fn missing_tool_call_ids(
  pending : Map[String, Bool],
  order : Array[String],
  approved : Map[String, Bool],
) -> Array[String] {
  let missing : Array[String] = []
  for id in order {
    if approved.get(id) is Some(_) {
      pending[id] = false
    }
    if pending.get(id) is Some(true) {
      missing.push(id)
    }
  }
  missing
}

///|
/// Validate and normalize model messages before provider conversion.
fn normalize_model_messages(
  messages : Array[@provider_utils.ModelMessage],
) -> Array[@provider_utils.ModelMessage] raise {
  let approved = approved_tool_call_ids(messages)
  let normalized : Array[@provider_utils.ModelMessage] = []
  for message in messages {
    let current = normalize_model_message(message)
    match current.role {
      @provider_utils.ModelTool(_) if current.content == "" &&
        current.parts.length() == 0 => ()
      _ => normalized.push(current)
    }
  }
  let combined = merge_structured_tool_messages(normalized)

  let pending : Map[String, Bool] = Map([])
  let order : Array[String] = []
  for message in combined {
    match message.role {
      @provider_utils.ModelAssistant => {
        for call in message.tool_calls {
          add_pending_tool_call(call, pending, order)
        }
        for part in message.parts {
          match part.without_provider_options() {
            @provider_utils.ModelToolCallPart(call~) =>
              add_pending_tool_call(call, pending, order)
            _ => ()
          }
        }
      }
      @provider_utils.ModelTool(tool_call_id) => {
        if tool_call_id != "" {
          pending[tool_call_id] = false
        }
        for part in message.parts {
          match part.without_provider_options() {
            @provider_utils.ModelToolResultPart(result~) =>
              pending[result.tool_call_id] = false
            _ => ()
          }
        }
      }
      @provider_utils.ModelSystem | @provider_utils.ModelUser => {
        let missing = missing_tool_call_ids(pending, order, approved)
        if missing.length() > 0 {
          raise @provider.MissingToolResultsError(tool_call_ids=missing)
        }
      }
    }
  }
  let missing = missing_tool_call_ids(pending, order, approved)
  if missing.length() > 0 {
    raise @provider.MissingToolResultsError(tool_call_ids=missing)
  }
  combined
}
