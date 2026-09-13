///|
/// A workflow run failed structurally (bad snapshot payload, failed output
/// validation, harness turn failure).
pub suberror WorkflowError {
  WorkflowError(message~ : String)
} derive(Debug, Eq)

///|
/// Serializable snapshot of a workflow run: the conversation so far plus the
/// completed step count. Persisting the JSON restores the run (resume) with
/// full history intact.
pub(all) struct WorkflowSessionSnapshot {
  agent_id : String?
  messages : Array[@provider_utils.ModelMessage]
  steps : Int
} derive(Debug)

///|
fn workflow_message_to_json(message : @provider_utils.ModelMessage) -> Json {
  let fields : Map[String, Json] = Map([])
  match message.role {
    @provider_utils.ModelSystem => fields["role"] = Json::string("system")
    @provider_utils.ModelUser => fields["role"] = Json::string("user")
    @provider_utils.ModelAssistant => fields["role"] = Json::string("assistant")
    @provider_utils.ModelTool(tool_call_id) => {
      fields["role"] = Json::string("tool")
      fields["tool_call_id"] = Json::string(tool_call_id)
    }
  }
  if message.content != "" {
    fields["content"] = Json::string(message.content)
  }
  if message.reasoning_content is Some(value) {
    fields["reasoning_content"] = Json::string(value)
  }
  if message.tool_calls.length() > 0 {
    let calls : Array[Json] = []
    for call in message.tool_calls {
      calls.push({
        "id": call.id,
        "name": call.name,
        "input": call.input,
        "provider_executed": call.provider_executed,
        "dynamic": call.dynamic,
      })
    }
    fields["tool_calls"] = Json::array(calls)
  }
  Json::object(fields)
}

///|
fn workflow_message_from_json(
  value : Json,
) -> @provider_utils.ModelMessage raise {
  guard value is Object(fields) else {
    raise WorkflowError(message="snapshot message must be an object")
  }
  let role = match fields.get("role") {
    Some(String(role)) => role
    _ => raise WorkflowError(message="snapshot message missing role")
  }
  let content = match fields.get("content") {
    Some(String(text)) => text
    _ => ""
  }
  let reasoning = match fields.get("reasoning_content") {
    Some(String(text)) => Some(text)
    _ => None
  }
  match role {
    "system" =>
      if reasoning is Some(_) {
        raise WorkflowError(
          message="system messages carry no reasoning_content",
        )
      } else {
        @provider_utils.ModelMessage::system(content)
      }
    "user" => @provider_utils.ModelMessage::user(content)
    "assistant" => {
      let tool_calls : Array[@provider_utils.ModelToolCall] = []
      match fields.get("tool_calls") {
        Some(Array(calls)) =>
          for call in calls {
            match call {
              { "id": String(id), "name": String(name), "input": input, .. } =>
                tool_calls.push(
                  @provider_utils.ModelToolCall::new(
                    id~,
                    name~,
                    input~,
                    provider_executed=false,
                    dynamic=false,
                  ),
                )
              _ =>
                raise WorkflowError(
                  message="snapshot tool call missing id/name/input",
                )
            }
          }
        _ => ()
      }
      @provider_utils.ModelMessage::assistant(
        content,
        tool_calls~,
        reasoning_content?=reasoning,
      )
    }
    "tool" =>
      match fields.get("tool_call_id") {
        Some(String(tool_call_id)) =>
          if reasoning is Some(_) {
            raise WorkflowError(
              message="tool messages carry no reasoning_content",
            )
          } else {
            @provider_utils.ModelMessage::tool(tool_call_id, content)
          }
        _ =>
          raise WorkflowError(
            message="tool snapshot message missing tool_call_id",
          )
      }
    other => raise WorkflowError(message="unknown snapshot role \{other}")
  }
}

///|
/// Serialize a workflow session snapshot to JSON.
pub fn workflow_snapshot_to_json(snapshot~ : WorkflowSessionSnapshot) -> Json {
  let fields : Map[String, Json] = Map([])
  if snapshot.agent_id is Some(id) {
    fields["agentId"] = Json::string(id)
  }
  fields["steps"] = Json::number(snapshot.steps.to_double())
  fields["messages"] = Json::array(
    [
      for message in snapshot.messages => workflow_message_to_json(message)
    ],
  )
  Json::object(fields)
}

///|
/// Deserialize a workflow session snapshot from JSON produced by
/// `workflow_snapshot_to_json`.
pub fn workflow_snapshot_from_json(
  value : Json,
) -> WorkflowSessionSnapshot raise {
  guard value is Object(fields) else {
    raise WorkflowError(message="workflow snapshot must be an object")
  }
  let agent_id = match fields.get("agentId") {
    Some(String(id)) => Some(id)
    _ => None
  }
  let steps = match fields.get("steps") {
    Some(Number(count, ..)) => count.to_int()
    _ => 0
  }
  let messages : Array[@provider_utils.ModelMessage] = []
  match fields.get("messages") {
    Some(Array(items)) =>
      for item in items {
        messages.push(workflow_message_from_json(item))
      }
    _ => ()
  }
  { agent_id, messages, steps, }
}
