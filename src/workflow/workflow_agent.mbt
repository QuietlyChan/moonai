///|
/// A workflow agent: an arbitrary `Agent` implementation (typically
/// `ToolLoopAgent`) wrapped with resumable session persistence and optional
/// structured-output validation. Mirrors the upstream WorkflowAgent core:
/// multi-turn runs keep their history in a serializable snapshot so a run can
/// be resumed after interruption.
pub struct WorkflowAgent {
  priv inner : &@agent.Agent
  priv output : WorkflowOutputSpecification?
  priv agent_id : String?
  priv mut messages : Array[@provider_utils.ModelMessage]
  priv mut steps : Int
}

///|
/// The result of one workflow agent run.
pub(all) struct WorkflowAgentResult {
  text : String
  output : Json?
  steps : Int
  usage : @provider.LanguageModelV4Usage
  snapshot : WorkflowSessionSnapshot
} derive(Debug)

///|
/// Create a workflow agent around an inner agent.
pub fn WorkflowAgent::new(
  agent~ : &@agent.Agent,
  output? : WorkflowOutputSpecification,
) -> WorkflowAgent {
  WorkflowAgent::{
    inner: agent,
    output,
    agent_id: agent.id(),
    messages: [],
    steps: 0,
  }
}

///|
/// Restore a previously persisted snapshot: conversation history and step
/// count continue from where the run left off.
pub fn WorkflowAgent::restore(
  self : WorkflowAgent,
  snapshot~ : WorkflowSessionSnapshot,
) -> Unit {
  self.messages = snapshot.messages.copy()
  self.steps = snapshot.steps
}

///|
/// Serialize the current session state for persistence.
pub fn WorkflowAgent::snapshot(self : WorkflowAgent) -> Json {
  workflow_snapshot_to_json(snapshot={
    agent_id: self.agent_id,
    messages: self.messages.copy(),
    steps: self.steps,
  })
}

///|
/// The conversation history accumulated across runs.
pub fn WorkflowAgent::messages(
  self : WorkflowAgent,
) -> Array[@provider_utils.ModelMessage] {
  self.messages.copy()
}

///|
/// Run one workflow turn. The user prompt is appended to the session history,
/// the inner agent generates, structured output is validated when a
/// specification is present, and the assistant reply is persisted into the
/// snapshot before the result returns.
pub async fn WorkflowAgent::generate(
  self : WorkflowAgent,
  options~ : @agent.AgentCallOptions,
) -> WorkflowAgentResult {
  match options.prompt {
    Some(prompt) =>
      self.messages.push(@provider_utils.ModelMessage::user(prompt))
    None => ()
  }
  for message in options.messages {
    self.messages.push(message)
  }
  let result = self.inner.generate(
    @agent.AgentCallOptions::new(
      messages=self.messages.copy(),
      runtime_context?=options.runtime_context,
      tools_context?=options.tools_context,
      cancellation_token?=options.cancellation_token,
      experimental_sandbox?=options.experimental_sandbox,
    ),
  )
  let text = result.text()
  self.steps = self.steps + 1
  let output : Json? = match self.output {
    Some(spec) => Some(validate_workflow_output(spec~, text~))
    None => None
  }
  self.messages.push(@provider_utils.ModelMessage::assistant(text))
  {
    text,
    output,
    steps: self.steps,
    usage: result.total_usage,
    snapshot: {
      agent_id: self.agent_id,
      messages: self.messages.copy(),
      steps: self.steps,
    },
  }
}
