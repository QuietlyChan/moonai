///|
/// Snapshot of the merged agent settings and call options handed to a
/// `prepare_call` hook. The hook may rewrite model-facing settings (tools,
/// instructions, headers, sampling controls, ...) per invocation.
pub(all) struct AgentCallDraft {
  settings : ToolLoopAgentSettings
  call : AgentCallOptions
}

///|
/// Settings for a tool loop agent.
///
/// The loop calls the model and, when tool calls come back, executes the
/// tools and calls the model again with the results. It stops when a finish
/// reason other than tool-calls arrives, a tool without an execute function
/// is invoked, an approval is required, or a stop condition is met.
pub(all) struct ToolLoopAgentSettings {
  /// The id of the agent.
  id : String?
  /// The language model driving the loop.
  model : &@provider.LanguageModelV4
  /// The tools the agent can use.
  tools : @provider_utils.ToolSet
  tool_choice : @provider.ToolChoice
  /// Stop conditions; defaults to exactly 20 steps.
  stop_when : Array[@generate_text.StopCondition]?
  instructions : @prompt.Instructions?
  allow_system_in_messages : Bool
  max_output_tokens : Int?
  temperature : Double?
  top_p : Double?
  seed : Int?
  stop_sequences : Array[String]
  response_format : @provider.ResponseFormat
  reasoning_effort : @provider.ReasoningEffort
  headers : Map[String, String]
  provider_options : Map[String, Json]
  runtime_context : Json
  tools_context : Map[String, Json]
  retry_policy : @provider.RetryPolicy
  experimental_sandbox : @provider_utils.SandboxSession?
  experimental_download : @prompt.DownloadFunction?
  /// Hook that observes and may rewrite the merged call before dispatch.
  prepare_call : ((AgentCallDraft) -> AgentCallDraft)?
}

///|
/// Construct tool loop agent settings with AI SDK defaults.
pub fn ToolLoopAgentSettings::new(
  model~ : &@provider.LanguageModelV4,
  id? : String,
  tools? : @provider_utils.ToolSet = Map([]),
  tool_choice? : @provider.ToolChoice = @provider.Auto,
  stop_when? : Array[@generate_text.StopCondition],
  instructions? : @prompt.Instructions,
  allow_system_in_messages? : Bool = false,
  max_output_tokens? : Int,
  temperature? : Double,
  top_p? : Double,
  seed? : Int,
  stop_sequences? : Array[String] = [],
  response_format? : @provider.ResponseFormat = @provider.Text,
  reasoning_effort? : @provider.ReasoningEffort = @provider.ProviderDefault,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  runtime_context? : Json = Json::empty_object(),
  tools_context? : Map[String, Json] = Map([]),
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  experimental_sandbox? : @provider_utils.SandboxSession,
  experimental_download? : @prompt.DownloadFunction,
  prepare_call? : ((AgentCallDraft) -> AgentCallDraft)? = None,
) -> ToolLoopAgentSettings {
  {
    id,
    model,
    tools,
    tool_choice,
    stop_when,
    instructions,
    allow_system_in_messages,
    max_output_tokens,
    temperature,
    top_p,
    seed,
    stop_sequences,
    response_format,
    reasoning_effort,
    headers: @provider_utils.copy_headers(headers),
    provider_options: @provider.copy_provider_metadata(provider_options),
    runtime_context,
    tools_context,
    retry_policy,
    experimental_sandbox,
    experimental_download,
    prepare_call,
  }
}

///|
/// A tool loop agent is an agent that runs tools in a loop. In each step it
/// calls the LLM and, when tool calls come back, executes the tools and
/// calls the LLM again with the results.
///
/// Outgoing requests are tagged with an `ai-sdk-agent/tool-loop` user-agent
/// suffix so usage can be attributed to the agent.
pub struct ToolLoopAgent {
  priv settings : ToolLoopAgentSettings
}

///|
/// Construct a tool loop agent from its settings.
pub fn ToolLoopAgent::new(settings~ : ToolLoopAgentSettings) -> ToolLoopAgent {
  { settings, }
}

///|
/// Read the agent settings.
pub fn ToolLoopAgent::settings(self : ToolLoopAgent) -> ToolLoopAgentSettings {
  self.settings
}

///|
/// Merge the agent settings with per-call options; call-level values win.
fn ToolLoopAgent::prepare_call(
  self : ToolLoopAgent,
  options : AgentCallOptions,
) -> ToolLoopAgentSettings {
  let merged_runtime_context = options.runtime_context.unwrap_or(
    self.settings.runtime_context,
  )
  let merged_tools_context = options.tools_context.unwrap_or(
    self.settings.tools_context,
  )
  let draft = {
    settings: self.settings,
    call: AgentCallOptions::new(
      prompt?=options.prompt,
      messages=options.messages,
      runtime_context=merged_runtime_context,
      tools_context=merged_tools_context,
      cancellation_token?=options.cancellation_token,
      experimental_sandbox?=options.experimental_sandbox,
    ),
  }
  match self.settings.prepare_call {
    Some(transform) => transform(draft).settings
    None => draft.settings
  }
}

///|
fn ToolLoopAgent::agent_headers(self : ToolLoopAgent) -> Map[String, String] {
  // Tags outgoing requests so usage can be attributed to ToolLoopAgent;
  // chains with the provider user-agent suffixes added downstream.
  @provider_utils.with_user_agent_suffix(self.settings.headers, [
    "ai-sdk-agent/tool-loop",
  ])
}

///|
pub impl Agent for ToolLoopAgent with fn version(_self : ToolLoopAgent) -> String {
  AGENT_VERSION
}

///|
pub impl Agent for ToolLoopAgent with fn id(self : ToolLoopAgent) -> String? {
  self.settings.id
}

///|
pub impl Agent for ToolLoopAgent with fn tools(self : ToolLoopAgent) -> @provider_utils.ToolSet {
  self.settings.tools
}

///|
pub impl Agent for ToolLoopAgent with fn generate(
  self : ToolLoopAgent,
  options : AgentCallOptions,
) -> @generate_text.GenerateTextResult raise {
  let settings = self.prepare_call(options)
  @generate_text.generate_text(
    settings.model,
    prompt?=options.prompt,
    messages=options.messages,
    instructions?=settings.instructions,
    allow_system_in_messages=settings.allow_system_in_messages,
    tools=settings.tools,
    tool_choice=settings.tool_choice,
    stop_when=settings.stop_when.unwrap_or([@generate_text.is_step_count(20)]),
    response_format=settings.response_format,
    reasoning_effort=settings.reasoning_effort,
    max_output_tokens?=settings.max_output_tokens,
    temperature?=settings.temperature,
    top_p?=settings.top_p,
    seed?=settings.seed,
    stop_sequences=settings.stop_sequences,
    headers=self.agent_headers(),
    provider_options=settings.provider_options,
    runtime_context=options.runtime_context.unwrap_or(settings.runtime_context),
    tools_context=options.tools_context.unwrap_or(settings.tools_context),
    experimental_sandbox?=match options.experimental_sandbox {
      Some(_) => options.experimental_sandbox
      None => settings.experimental_sandbox
    },
    experimental_download?=settings.experimental_download,
    retry_policy=settings.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}

///|
pub impl Agent for ToolLoopAgent with fn stream(
  self : ToolLoopAgent,
  options : AgentCallOptions,
) -> @generate_text.StreamTextResult raise {
  let settings = self.prepare_call(options)
  @generate_text.stream_text(
    settings.model,
    prompt?=options.prompt,
    messages=options.messages,
    instructions?=settings.instructions,
    allow_system_in_messages=settings.allow_system_in_messages,
    tools=settings.tools,
    tool_choice=settings.tool_choice,
    stop_when=settings.stop_when.unwrap_or([@generate_text.is_step_count(20)]),
    response_format=settings.response_format,
    reasoning_effort=settings.reasoning_effort,
    max_output_tokens?=settings.max_output_tokens,
    temperature?=settings.temperature,
    top_p?=settings.top_p,
    seed?=settings.seed,
    stop_sequences=settings.stop_sequences,
    headers=self.agent_headers(),
    provider_options=settings.provider_options,
    runtime_context=options.runtime_context.unwrap_or(settings.runtime_context),
    tools_context=options.tools_context.unwrap_or(settings.tools_context),
    experimental_sandbox?=match options.experimental_sandbox {
      Some(_) => options.experimental_sandbox
      None => settings.experimental_sandbox
    },
    experimental_download?=settings.experimental_download,
    retry_policy=settings.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}
