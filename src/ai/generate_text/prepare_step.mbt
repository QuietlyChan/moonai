///|
/// Tool names enabled for a generation step.
pub type ActiveTools = Array[String]

///|
/// Preferred order for tools sent to the provider. Names omitted from this
/// list are appended alphabetically.
pub type ToolOrder = Array[String]

///|
/// Read-only inputs supplied to a `prepareStep` callback before each model
/// call. Message arrays are isolated from the workflow's mutable state.
pub(all) struct PrepareStepOptions {
  steps : Array[GenerateTextStep]
  step_number : Int
  model : &@provider.LanguageModelV4
  instructions : @prompt.Instructions?
  initial_instructions : @prompt.Instructions?
  messages : Array[@provider_utils.ModelMessage]
  initial_messages : Array[@provider_utils.ModelMessage]
  response_messages : Array[@provider_utils.ModelMessage]
  runtime_context : Json
  tools_context : Map[String, Json]
  experimental_sandbox : @provider_utils.SandboxSession?
}

///|
/// Per-step overrides returned by `prepareStep`.
///
/// Model call settings apply only to the current step. Instructions, messages,
/// runtime context, and tool context carry forward to subsequent steps.
pub(all) struct PrepareStepResult {
  model : &@provider.LanguageModelV4?
  tool_choice : @provider.ToolChoice?
  active_tools : ActiveTools?
  tool_order : ToolOrder?
  instructions : @prompt.Instructions?
  messages : Array[@provider_utils.ModelMessage]?
  runtime_context : Json?
  tools_context : Map[String, Json]?
  experimental_sandbox : @provider_utils.SandboxSession?
  provider_options : Map[String, Json]?
  max_output_tokens : Int?
  temperature : Double?
  top_p : Double?
  top_k : Double?
  frequency_penalty : Double?
  presence_penalty : Double?
  seed : Int?
  stop_sequences : Array[String]?
  reasoning_effort : @provider.ReasoningEffort?
}

///|
/// Construct a set of per-step overrides. Omitted values fall back to the
/// outer `generateText` or `streamText` settings.
pub fn PrepareStepResult::new(
  model? : &@provider.LanguageModelV4,
  tool_choice? : @provider.ToolChoice,
  active_tools? : ActiveTools,
  tool_order? : ToolOrder,
  instructions? : @prompt.Instructions,
  messages? : Array[@provider_utils.ModelMessage],
  runtime_context? : Json,
  tools_context? : Map[String, Json],
  experimental_sandbox? : @provider_utils.SandboxSession,
  provider_options? : Map[String, Json],
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  top_k? : Double,
  frequency_penalty? : Double,
  presence_penalty? : Double,
  seed? : Int,
  stop_sequences? : Array[String],
  reasoning_effort? : @provider.ReasoningEffort,
) -> PrepareStepResult {
  {
    model,
    tool_choice,
    active_tools: match active_tools {
      Some(value) => Some(value.copy())
      None => None
    },
    tool_order: match tool_order {
      Some(value) => Some(value.copy())
      None => None
    },
    instructions,
    messages: match messages {
      Some(value) => Some(copy_model_messages(value))
      None => None
    },
    runtime_context,
    tools_context: match tools_context {
      Some(value) => Some(@provider.copy_provider_metadata(value))
      None => None
    },
    experimental_sandbox,
    provider_options: match provider_options {
      Some(value) => Some(@provider.copy_provider_metadata(value))
      None => None
    },
    max_output_tokens,
    temperature,
    top_p,
    top_k,
    frequency_penalty,
    presence_penalty,
    seed,
    stop_sequences: match stop_sequences {
      Some(value) => Some(value.copy())
      None => None
    },
    reasoning_effort,
  }
}

///|
/// Callback used to prepare one generation step.
pub type PrepareStepFunction = async (PrepareStepOptions) -> PrepareStepResult?

///|
priv struct GenerationStepDefaults {
  model : &@provider.LanguageModelV4
  tools : @provider_utils.ToolSet
  resolved_tool_callers : @tool.ResolvedToolCallers?
  active_tools : ActiveTools?
  tool_order : ToolOrder?
  tool_choice : @provider.ToolChoice
  call_settings : @prompt.LanguageModelCallOptions
  provider_options : Map[String, Json]
}

///|
priv struct PreparedGenerationStep {
  model : &@provider.LanguageModelV4
  instructions : @prompt.Instructions?
  messages : Array[@provider_utils.ModelMessage]
  execution_tools : @provider_utils.ToolSet
  model_tools : @provider_utils.ToolSet
  tool_choice : @provider.ToolChoice
  call_settings : @prompt.LanguageModelCallOptions
  provider_options : Map[String, Json]
  runtime_context : Json
  tools_context : Map[String, Json]
  experimental_sandbox : @provider_utils.SandboxSession?
}

///|
fn copy_optional_names(values : Array[String]?) -> Array[String]? {
  match values {
    Some(value) => Some(value.copy())
    None => None
  }
}

///|
fn[T] step_value_or(value : T?, fallback : T?) -> T? {
  match value {
    Some(_) => value
    None => fallback
  }
}

///|
fn create_generation_step_defaults(
  model : &@provider.LanguageModelV4,
  tools : @provider_utils.ToolSet,
  resolved_tool_callers : @tool.ResolvedToolCallers?,
  active_tools : ActiveTools?,
  tool_order : ToolOrder?,
  tool_choice : @provider.ToolChoice,
  call_settings : @prompt.LanguageModelCallOptions,
  provider_options : Map[String, Json],
) -> GenerationStepDefaults {
  {
    model,
    tools: @provider_utils.copy_tool_set(tools),
    resolved_tool_callers,
    active_tools: copy_optional_names(active_tools),
    tool_order: copy_optional_names(tool_order),
    tool_choice,
    call_settings,
    provider_options: @provider.copy_provider_metadata(provider_options),
  }
}

///|
fn filter_active_tools(
  tools : @provider_utils.ToolSet,
  active_tools : ActiveTools?,
) -> @provider_utils.ToolSet {
  guard active_tools is Some(names) else {
    return @provider_utils.copy_tool_set(tools)
  }
  let selected : Map[String, Bool] = Map([])
  for name in names {
    selected[name] = true
  }
  let result : @provider_utils.ToolSet = Map([])
  for entry in tools.iter2() {
    if selected.get(entry.0) is Some(_) {
      result[entry.0] = entry.1
    }
  }
  result
}

///|
fn order_tool_set(
  tools : @provider_utils.ToolSet,
  tool_order : ToolOrder?,
) -> @provider_utils.ToolSet {
  guard tool_order is Some(order) else {
    return @provider_utils.copy_tool_set(tools)
  }
  let result : @provider_utils.ToolSet = Map([])
  for name in order {
    match tools.get(name) {
      Some(tool) => result[name] = tool
      None => ()
    }
  }
  let remaining = [
    for entry in tools.iter2() if result.get(entry.0) is None => entry
  ]
  remaining.sort_by((left, right) => left.0.compare(right.0))
  for entry in remaining {
    result[entry.0] = entry.1
  }
  result
}

///|
/// Resolve step-local tool descriptions after caller routing and ordering.
/// Execution tools remain unchanged; only the definitions sent to the model
/// receive the derived descriptions.
fn resolve_tool_descriptions(
  tools : @provider_utils.ToolSet,
  tools_context : Map[String, Json],
  experimental_sandbox : @provider_utils.SandboxSession?,
) -> @provider_utils.ToolSet {
  let result : @provider_utils.ToolSet = Map([])
  for entry in tools.iter2() {
    let (name, tool) = entry
    result[name] = tool.resolve_description(
      context=tools_context.get(name).unwrap_or(Json::empty_object()),
      experimental_sandbox?,
    )
  }
  result
}

///|
fn prepare_step_call_settings(
  defaults : @prompt.LanguageModelCallOptions,
  overrides : PrepareStepResult?,
) -> @prompt.LanguageModelCallOptions raise {
  let max_output_tokens = overrides.bind(value => value.max_output_tokens)
    |> step_value_or(defaults.max_output_tokens)
  let temperature = overrides.bind(value => value.temperature)
    |> step_value_or(defaults.temperature)
  let top_p = overrides.bind(value => value.top_p)
    |> step_value_or(defaults.top_p)
  let top_k = overrides.bind(value => value.top_k)
    |> step_value_or(defaults.top_k)
  let frequency_penalty = overrides.bind(value => value.frequency_penalty)
    |> step_value_or(defaults.frequency_penalty)
  let presence_penalty = overrides.bind(value => value.presence_penalty)
    |> step_value_or(defaults.presence_penalty)
  let seed = overrides.bind(value => value.seed) |> step_value_or(defaults.seed)
  let stop_sequences = match overrides.bind(value => value.stop_sequences) {
    Some(value) => value.copy()
    None => defaults.stop_sequences.copy()
  }
  let reasoning_effort = overrides
    .bind(value => value.reasoning_effort)
    .unwrap_or(defaults.reasoning_effort)
  @prompt.prepare_language_model_call_options(
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
}

///|
async fn prepare_generation_step(
  defaults : GenerationStepDefaults,
  options : PrepareStepOptions,
  prepare_step : PrepareStepFunction?,
) -> PreparedGenerationStep {
  let overrides = match prepare_step {
    Some(prepare) => prepare(options)
    None => None
  }
  let model = overrides.bind(value => value.model).unwrap_or(defaults.model)
  let instructions = overrides.bind(value => value.instructions)
    |> step_value_or(options.instructions)
  let messages = match overrides.bind(value => value.messages) {
    Some(value) => copy_model_messages(value)
    None => copy_model_messages(options.messages)
  }
  let runtime_context = overrides
    .bind(value => value.runtime_context)
    .unwrap_or(options.runtime_context)
  let tools_context = match overrides.bind(value => value.tools_context) {
    Some(value) => @provider.copy_provider_metadata(value)
    None => @provider.copy_provider_metadata(options.tools_context)
  }
  let experimental_sandbox = overrides.bind(value => value.experimental_sandbox)
    |> step_value_or(options.experimental_sandbox)
  let active_tools = match overrides.bind(value => value.active_tools) {
    Some(value) => Some(value.copy())
    None => copy_optional_names(defaults.active_tools)
  }
  let tool_order = match overrides.bind(value => value.tool_order) {
    Some(value) => Some(value.copy())
    None => copy_optional_names(defaults.tool_order)
  }
  let active_tool_set = filter_active_tools(defaults.tools, active_tools)
  let prepared_tools = @tool.prepare_tools_for_tool_callers(
    active_tool_set,
    defaults.resolved_tool_callers,
  )
  let model_tools = resolve_tool_descriptions(
    order_tool_set(prepared_tools.model_tools(), tool_order),
    tools_context,
    experimental_sandbox,
  )
  let provider_options = match overrides.bind(value => value.provider_options) {
    Some(value) =>
      @provider.merge_provider_metadata(defaults.provider_options, value)
    None => @provider.copy_provider_metadata(defaults.provider_options)
  }
  {
    model,
    instructions,
    messages,
    execution_tools: prepared_tools.execution_tools(),
    model_tools,
    tool_choice: overrides
    .bind(value => value.tool_choice)
    .unwrap_or(defaults.tool_choice),
    call_settings: prepare_step_call_settings(defaults.call_settings, overrides),
    provider_options,
    runtime_context,
    tools_context,
    experimental_sandbox,
  }
}
