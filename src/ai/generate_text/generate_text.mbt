///|
fn copy_model_messages(
  messages : Array[@provider_utils.ModelMessage],
) -> Array[@provider_utils.ModelMessage] {
  [
    for message in messages => message.copy()
  ]
}

///|
fn client_tool_call_count(calls : Array[GenerateTextToolCall]) -> Int {
  let mut count = 0
  for call in calls {
    if !call.provider_executed {
      count = count + 1
    }
  }
  count
}

///|
fn tool_results_from_content(
  content : Array[GenerateTextContent],
) -> Array[GenerateTextToolResult] {
  let results : Array[GenerateTextToolResult] = []
  for part in content {
    match part {
      GenerateTextToolResult(value) => results.push(value)
      _ => ()
    }
  }
  results
}

///|
fn has_tool_result(
  content : Array[GenerateTextContent],
  tool_call_id : String,
) -> Bool {
  content.any(part => {
    match part {
      GenerateTextToolResult(value) => value.tool_call_id == tool_call_id
      _ => false
    }
  })
}

///|
fn update_pending_deferred_tool_calls(
  calls : Array[GenerateTextToolCall],
  content : Array[GenerateTextContent],
  tools : @provider_utils.ToolSet,
  pending : Map[String, String],
) -> Unit {
  for call in calls {
    guard call.provider_executed else { continue }
    match tools.get(call.tool_name) {
      Some(tool) if tool.supports_deferred_results() =>
        if !has_tool_result(content, call.tool_call_id) {
          pending[call.tool_call_id] = call.tool_name
        }
      _ => ()
    }
  }
  for part in content {
    match part {
      GenerateTextToolResult(result) if result.provider_executed =>
        pending.remove(result.tool_call_id)
      _ => ()
    }
  }
}

///|
/// Notify registered tools after non-streaming inputs have been validated.
async fn invoke_tool_input_callbacks(
  calls : Array[GenerateTextToolCall],
  tools : @provider_utils.ToolSet,
  messages : Array[@provider_utils.ModelMessage],
  cancellation_token : @provider.CancellationToken?,
  runtime_context : Json,
  experimental_sandbox : @provider_utils.SandboxSession?,
) -> Unit {
  for call in calls {
    guard !call.invalid else { continue }
    match tools.get(call.tool_name) {
      Some(tool) => {
        tool.invoke_input_start(
          @provider_utils.ToolExecutionOptions::new(
            tool_call_id=call.tool_call_id,
            messages~,
            cancellation_token?,
            context=runtime_context,
            experimental_sandbox?,
          ),
        )
        tool.invoke_input_available(
          @provider_utils.ToolInputAvailableOptions::new(
            input=call.input,
            tool_call_id=call.tool_call_id,
            messages~,
            cancellation_token?,
            context=runtime_context,
            experimental_sandbox?,
          ),
        )
      }
      None => ()
    }
  }
}

///|
fn optional_token_sum(first : Int?, second : Int?) -> Int? {
  if first is None && second is None {
    None
  } else {
    Some(first.unwrap_or(0) + second.unwrap_or(0))
  }
}

///|
fn tokens_per_second(tokens : Int?, duration_ms : Int) -> Double? {
  guard duration_ms > 0 else { return None }
  match tokens {
    Some(value) => Some(value.to_double() * 1000.0 / duration_ms.to_double())
    None => None
  }
}

///|
fn step_performance(
  usage : @provider.LanguageModelV4Usage,
  step_time_ms : Int,
  response_time_ms : Int,
  tool_execution_ms : Map[String, Int],
) -> GenerateTextStepPerformance {
  {
    step_time_ms,
    response_time_ms,
    tool_execution_ms,
    effective_output_tokens_per_second: tokens_per_second(
      usage.output_tokens.total,
      response_time_ms,
    ),
    effective_total_tokens_per_second: tokens_per_second(
      optional_token_sum(usage.input_tokens.total, usage.output_tokens.total),
      response_time_ms,
    ),
  }
}

///|
/// Generate text through the provider-neutral V4 contract.
///
/// The provider performs one model call at a time. This high-level layer owns
/// the AI SDK workflow around those calls: prompt history, tool-caller
/// preparation, tool input validation, client execution, response messages,
/// deferred provider-tool results, stop conditions, and step aggregation.
pub async fn generate_text(
  model : &@provider.LanguageModelV4,
  prompt? : String,
  messages? : Array[@provider_utils.ModelMessage] = [],
  instructions? : @prompt.Instructions,
  allow_system_in_messages? : Bool = false,
  tools? : @provider_utils.ToolSet = Map([]),
  tool_approval? : ToolApprovalConfiguration,
  experimental_tool_approval_secret? : ToolApprovalSecret,
  experimental_tool_callers? : @tool.ToolCallerConfiguration,
  active_tools? : ActiveTools,
  tool_order? : ToolOrder,
  prepare_step? : PrepareStepFunction,
  stop_when? : Array[StopCondition],
  tool_choice? : @provider.ToolChoice = @provider.Auto,
  response_format? : @provider.ResponseFormat = @provider.Text,
  reasoning_effort? : @provider.ReasoningEffort = @provider.ProviderDefault,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  top_k? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  include_raw_chunks? : Bool = false,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  runtime_context? : Json = Json::empty_object(),
  tools_context? : Map[String, Json] = Map([]),
  experimental_sandbox? : @provider_utils.SandboxSession,
  experimental_download? : @prompt.DownloadFunction,
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
) -> GenerateTextResult {
  @provider.check_cancellation(cancellation_token)
  let initial_prompt = @prompt.standardize_prompt(
    prompt,
    messages,
    instructions?,
    allow_system_in_messages~,
  )
  let initial_approval_messages = initial_tool_approval_result_messages(
    initial_prompt.messages,
    tools,
    tool_approval,
    experimental_tool_approval_secret,
    tools_context,
    runtime_context,
    cancellation_token,
    experimental_sandbox,
  )
  let resolved_tool_callers = @tool.resolve_tool_caller_configuration(
    tools, experimental_tool_callers,
  )
  let call_settings = @prompt.prepare_language_model_call_options(
    @prompt.LanguageModelCallOptions::new(
      max_output_tokens?,
      temperature?,
      top_p?,
      top_k?,
      presence_penalty?,
      frequency_penalty?,
      stop_sequences~,
      seed?,
      reasoning_effort~,
    ),
  )
  let step_defaults = create_generation_step_defaults(
    model, tools, resolved_tool_callers, active_tools, tool_order, tool_choice, call_settings,
    provider_options,
  )
  let stop_conditions = match stop_when {
    Some(values) => values.copy()
    None => [is_step_count(1)]
  }
  let call_id = @provider_utils.generate_id()
  let steps : Array[GenerateTextStep] = []
  let pending_deferred_tool_calls : Map[String, String] = Map([])
  let initial_messages = copy_model_messages(initial_prompt.messages)
  let accumulated_response_messages : Array[@provider_utils.ModelMessage] = []
  let starting_messages = copy_model_messages(initial_prompt.messages)
  for message in initial_approval_messages {
    starting_messages.push(message.copy())
  }
  let mut messages_for_next_step = starting_messages
  let mut instructions_for_next_step = initial_prompt.instructions
  let mut runtime_context_for_next_step = runtime_context
  let mut tools_context_for_next_step = @provider.copy_provider_metadata(
    tools_context,
  )
  while true {
    @provider.check_cancellation(cancellation_token)
    let prepared_step = prepare_generation_step(
      step_defaults,
      {
        steps: steps.copy(),
        step_number: steps.length(),
        model,
        instructions: instructions_for_next_step,
        initial_instructions: initial_prompt.instructions,
        messages: copy_model_messages(messages_for_next_step),
        initial_messages: copy_model_messages(initial_messages),
        response_messages: copy_model_messages(accumulated_response_messages),
        runtime_context: runtime_context_for_next_step,
        tools_context: @provider.copy_provider_metadata(
          tools_context_for_next_step,
        ),
        experimental_sandbox,
      },
      prepare_step,
    )
    @provider.check_cancellation(cancellation_token)
    let execution_tools = prepared_step.execution_tools
    let model_tools = prepared_step.model_tools
    let step_settings = prepared_step.call_settings
    let call_options = @prompt.prepare_language_model_v4_call_options(
      prepared_step.model,
      None,
      prepared_step.messages,
      prepared_step.instructions,
      allow_system_in_messages,
      @provider_utils.tool_definitions(model_tools),
      prepared_step.tool_choice,
      response_format,
      step_settings.reasoning_effort,
      step_settings.max_output_tokens,
      step_settings.temperature,
      step_settings.top_p,
      step_settings.top_k,
      step_settings.frequency_penalty,
      step_settings.presence_penalty,
      step_settings.seed,
      step_settings.stop_sequences,
      include_raw_chunks,
      headers,
      prepared_step.provider_options,
      experimental_download,
      retry_policy,
      cancellation_token,
    )
    let step_started_at = @env.now()
    let response_started_at = @env.now()
    let provider_result = prepared_step.model.do_generate(call_options)
    @provider.check_cancellation(cancellation_token)
    let response_time_ms = (@env.now() - response_started_at).to_int()
    let tool_calls = parse_tool_calls(provider_result.content, execution_tools)
    invoke_tool_input_callbacks(
      tool_calls,
      execution_tools,
      prepared_step.messages,
      cancellation_token,
      prepared_step.runtime_context,
      prepared_step.experimental_sandbox,
    )
    let provider_content = normalize_provider_content(
      provider_result.content,
      tool_calls,
    )
    let approvals = resolve_step_tool_approvals(
      tool_calls,
      execution_tools,
      tool_approval,
      experimental_tool_approval_secret,
      prepared_step.messages,
      prepared_step.tools_context,
      prepared_step.runtime_context,
    )
    let executed = execute_client_tool_calls(
      tool_calls,
      execution_tools,
      approvals.blocked_tool_call_ids,
      prepared_step.messages,
      prepared_step.tools_context,
      cancellation_token,
      prepared_step.experimental_sandbox,
    )
    @provider.check_cancellation(cancellation_token)
    let content = append_client_tool_results(
      append_tool_approvals(provider_content, approvals),
      executed.results,
    )
    update_pending_deferred_tool_calls(
      tool_calls, content, execution_tools, pending_deferred_tool_calls,
    )
    let response_messages = to_response_messages(content, execution_tools)
    let step_time_ms = (@env.now() - step_started_at).to_int()
    let step : GenerateTextStep = {
      call_id,
      step_number: steps.length(),
      provider: prepared_step.model.provider(),
      model_id: prepared_step.model.model_id(),
      runtime_context: prepared_step.runtime_context,
      tools_context: @provider.copy_provider_metadata(
        prepared_step.tools_context,
      ),
      content,
      tool_calls: tool_calls.copy(),
      tool_results: tool_results_from_content(content),
      tool_approval_requests: tool_approval_requests_from_content(content),
      tool_approval_responses: tool_approval_responses_from_content(content),
      finish_reason: provider_result.finish_reason,
      usage: provider_result.usage,
      performance: step_performance(
        provider_result.usage,
        step_time_ms,
        response_time_ms,
        executed.execution_ms,
      ),
      request: provider_result.request,
      response: provider_result.response,
      provider_metadata: @provider.copy_provider_metadata(
        provider_result.provider_metadata,
      ),
      warnings: @provider.copy_warnings(provider_result.warnings),
      response_messages: copy_model_messages(response_messages),
      provider_result,
    }
    steps.push(step)
    let next_messages = copy_model_messages(prepared_step.messages)
    for message in response_messages {
      next_messages.push(message.copy())
      accumulated_response_messages.push(message.copy())
    }
    messages_for_next_step = next_messages
    instructions_for_next_step = prepared_step.instructions
    runtime_context_for_next_step = prepared_step.runtime_context
    tools_context_for_next_step = @provider.copy_provider_metadata(
      prepared_step.tools_context,
    )
    let client_calls = client_tool_call_count(tool_calls)
    let has_complete_client_tools = client_calls > 0 &&
      executed.completed_count + approvals.denied_client_count == client_calls
    let has_pending_deferred_tools = pending_deferred_tool_calls.length() > 0
    let has_provider_approval_responses = approvals.provider_response_count > 0
    let stop = stop_condition_met(stop_conditions, steps)
    if !(has_complete_client_tools ||
      has_pending_deferred_tools ||
      has_provider_approval_responses) ||
      stop {
      break
    }
  }
  @provider.check_cancellation(cancellation_token)
  create_generate_text_result(steps)
}

///|
/// AI SDK-style camel-case spelling for `generate_text`.
pub async fn generateText(
  model : &@provider.LanguageModelV4,
  prompt? : String,
  messages? : Array[@provider_utils.ModelMessage] = [],
  instructions? : @prompt.Instructions,
  allow_system_in_messages? : Bool = false,
  tools? : @provider_utils.ToolSet = Map([]),
  tool_approval? : ToolApprovalConfiguration,
  experimental_tool_approval_secret? : ToolApprovalSecret,
  experimental_tool_callers? : @tool.ToolCallerConfiguration,
  active_tools? : ActiveTools,
  tool_order? : ToolOrder,
  prepare_step? : PrepareStepFunction,
  stop_when? : Array[StopCondition],
  tool_choice? : @provider.ToolChoice = @provider.Auto,
  response_format? : @provider.ResponseFormat = @provider.Text,
  reasoning_effort? : @provider.ReasoningEffort = @provider.ProviderDefault,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  top_k? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  include_raw_chunks? : Bool = false,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  runtime_context? : Json = Json::empty_object(),
  tools_context? : Map[String, Json] = Map([]),
  experimental_sandbox? : @provider_utils.SandboxSession,
  experimental_download? : @prompt.DownloadFunction,
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
) -> GenerateTextResult {
  generate_text(
    model,
    prompt?,
    messages~,
    instructions?,
    allow_system_in_messages~,
    tools~,
    tool_approval?,
    experimental_tool_approval_secret?,
    experimental_tool_callers?,
    active_tools?,
    tool_order?,
    prepare_step?,
    stop_when?,
    tool_choice~,
    response_format~,
    reasoning_effort~,
    max_output_tokens?,
    temperature?,
    top_p?,
    top_k?,
    frequency_penalty?,
    presence_penalty?,
    seed?,
    stop_sequences~,
    include_raw_chunks~,
    headers~,
    provider_options~,
    runtime_context~,
    tools_context~,
    experimental_sandbox?,
    experimental_download?,
    retry_policy~,
    cancellation_token?,
  )
}
