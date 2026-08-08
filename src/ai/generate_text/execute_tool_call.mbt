///|
priv struct ToolExecutionOutcome {
  result : GenerateTextToolResult
  execution_ms : Int
}

///|
priv struct ExecutedClientTools {
  results : Array[GenerateTextToolResult]
  completed_count : Int
  execution_ms : Map[String, Int]
}

///|
fn tool_error_result(
  call : GenerateTextToolCall,
  message : String,
) -> GenerateTextToolResult {
  {
    tool_call_id: call.tool_call_id,
    tool_name: call.tool_name,
    input: call.input,
    output: Json::string(message),
    is_error: true,
    preliminary: false,
    provider_executed: false,
    dynamic: call.dynamic,
    provider_metadata: @provider.copy_provider_metadata(call.provider_metadata),
  }
}

///|
async fn execute_tool_call(
  call : GenerateTextToolCall,
  tool : @provider_utils.Tool,
  messages : Array[@provider_utils.ModelMessage],
  context : Json,
  cancellation_token : @provider.CancellationToken?,
  experimental_sandbox : @provider_utils.SandboxSession?,
) -> ToolExecutionOutcome {
  let started_at = @env.now()
  let result = try
    tool.execute(
      call.input,
      @provider_utils.ToolExecutionOptions::new(
        tool_call_id=call.tool_call_id,
        messages~,
        cancellation_token?,
        context~,
        experimental_sandbox?,
      ),
    )
  catch {
    error => {
      if error is @provider.CancellationError || @async.is_being_cancelled() {
        raise error
      }
      let execution_ms = (@env.now() - started_at).to_int()
      return {
        result: tool_error_result(call, @debug.to_string(error)),
        execution_ms,
      }
    }
  } noraise {
    value => value
  }
  let execution_ms = (@env.now() - started_at).to_int()
  let output = match result {
    Some(value) => value
    None => Json::null()
  }
  {
    result: {
      tool_call_id: call.tool_call_id,
      tool_name: call.tool_name,
      input: call.input,
      output,
      is_error: false,
      preliminary: false,
      provider_executed: false,
      dynamic: call.dynamic,
      provider_metadata: @provider.copy_provider_metadata(
        call.provider_metadata,
      ),
    },
    execution_ms,
  }
}

///|
async fn execute_client_tool_calls(
  calls : Array[GenerateTextToolCall],
  tools : @provider_utils.ToolSet,
  blocked_tool_call_ids : Map[String, Bool],
  messages : Array[@provider_utils.ModelMessage],
  tools_context : Map[String, Json],
  cancellation_token : @provider.CancellationToken?,
  experimental_sandbox : @provider_utils.SandboxSession?,
) -> ExecutedClientTools {
  let results : Array[GenerateTextToolResult] = []
  let tasks : Array[async () -> ToolExecutionOutcome] = []
  for call in calls {
    guard !call.provider_executed else { continue }
    guard blocked_tool_call_ids.get(call.tool_call_id) is None else { continue }
    if call.invalid {
      results.push(
        tool_error_result(
          call,
          call.error.unwrap_or("The tool input is invalid."),
        ),
      )
      continue
    }
    match tools.get(call.tool_name) {
      Some(tool) if tool.is_executable() => {
        let current_call = call
        let current_tool = tool
        tasks.push(() => {
          @provider.check_cancellation(cancellation_token)
          execute_tool_call(
            current_call,
            current_tool,
            messages,
            tools_context
            .get(current_call.tool_name)
            .unwrap_or(Json::empty_object()),
            cancellation_token,
            experimental_sandbox,
          )
        })
      }
      _ => ()
    }
  }
  let execution_ms : Map[String, Int] = Map([])
  for outcome in @async.all(tasks) {
    execution_ms[outcome.result.tool_call_id] = outcome.execution_ms
    results.push(outcome.result)
  }
  { results, completed_count: results.length(), execution_ms }
}
