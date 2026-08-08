///|
/// Stream text through the provider-neutral V4 contract.
///
/// Provider events remain visible through `on_event`. Once a streamed step
/// finishes, this high-level layer assembles its completed content, validates
/// and executes client tools, appends response messages, and starts another
/// provider stream when the stop conditions permit. This mirrors the same
/// workflow ownership as `generateText` while keeping protocol decoding in
/// provider packages.
pub async fn stream_text(
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
  on_event? : async (@provider.LanguageModelV4StreamPart) -> Unit = _ => (),
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
) -> StreamTextResult {
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
    let accumulator = StreamStepAccumulator::new()
    let ongoing_tool_call_names : Map[String, String] = Map([])
    let stream_result = prepared_step.model.do_stream(call_options, event => {
      accumulator.process(event)
      on_event(event)
      invoke_tool_callbacks_from_stream_part(
        event,
        execution_tools,
        ongoing_tool_call_names,
        prepared_step.messages,
        cancellation_token,
        prepared_step.runtime_context,
        prepared_step.experimental_sandbox,
      )
    })
    @provider.check_cancellation(cancellation_token)
    let response_time_ms = (@env.now() - response_started_at).to_int()
    let provider_result = accumulator.provider_result(stream_result)
    let tool_calls = parse_tool_calls(provider_result.content, execution_tools)
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
  create_stream_text_result(steps)
}

///|
/// AI SDK-style camel-case spelling for `stream_text`.
pub async fn streamText(
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
  on_event? : async (@provider.LanguageModelV4StreamPart) -> Unit = _ => (),
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
) -> StreamTextResult {
  stream_text(
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
    on_event~,
    retry_policy~,
    cancellation_token?,
  )
}
