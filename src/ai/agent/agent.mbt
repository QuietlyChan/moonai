///|
/// Specification version reported by Agent implementations.
pub const AGENT_VERSION : String = "agent-v1"

///|
/// Per-call parameters for an agent invocation.
///
/// A call provides the prompt (text or messages) plus transient overrides;
/// everything else comes from the agent's settings. Call-level values win
/// over settings.
pub(all) struct AgentCallOptions {
  /// A text prompt. Either the prompt or messages must be provided.
  prompt : String?
  /// A list of messages. Either the prompt or messages must be provided.
  messages : Array[@provider_utils.ModelMessage]
  /// Per-call runtime context; overrides the agent setting when present.
  runtime_context : Json?
  /// Per-call tool context; overrides the agent setting when present.
  tools_context : Map[String, Json]?
  /// Cooperative cancellation signal.
  cancellation_token : @provider.CancellationToken?
  /// Sandbox session passed through to tool execution.
  experimental_sandbox : @provider_utils.SandboxSession?
}

///|
/// Construct agent call options.
pub fn AgentCallOptions::new(
  prompt? : String,
  messages? : Array[@provider_utils.ModelMessage] = [],
  runtime_context? : Json,
  tools_context? : Map[String, Json],
  cancellation_token? : @provider.CancellationToken,
  experimental_sandbox? : @provider_utils.SandboxSession,
) -> AgentCallOptions {
  {
    prompt,
    messages,
    runtime_context,
    tools_context,
    cancellation_token,
    experimental_sandbox,
  }
}

///|
/// An Agent receives a prompt (text or messages) and generates or streams
/// an output that consists of steps, tool calls, and results.
///
/// Implement this trait to build custom agents, or use `ToolLoopAgent` for
/// the standard tool-calling loop.
pub(open) trait Agent {
  /// The specification version of the agent interface.
  fn version(Self) -> String
  /// The id of the agent, if one was configured.
  fn id(Self) -> String?
  /// The tools that the agent can use.
  fn tools(Self) -> @provider_utils.ToolSet
  /// Generates an output from the agent (non-streaming).
  async fn generate(Self, AgentCallOptions) -> @generate_text.GenerateTextResult
  /// Streams an output from the agent (streaming).
  async fn stream(Self, AgentCallOptions) -> @generate_text.StreamTextResult
}
