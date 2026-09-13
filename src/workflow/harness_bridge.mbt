///|
/// Bridges a harness session into a workflow step: one prompt turn is driven
/// against the harness `HarnessV1Session` while its stream parts are folded
/// into a workflow-level turn result (text plus tool-activity counts).
pub struct WorkflowHarnessBridge {
  session : &@harness.HarnessV1Session
}

///|
/// The outcome of one bridged harness turn.
pub(all) struct WorkflowHarnessTurnResult {
  text : String
  reasoning : String
  tool_inputs_started : Int
  events : Int
} derive(Debug, Eq)

///|
/// Wrap a harness session for workflow consumption.
pub fn WorkflowHarnessBridge::new(
  session~ : &@harness.HarnessV1Session,
) -> WorkflowHarnessBridge {
  { session, }
}

///|
/// Run one prompt turn against the harness and collect the streamed text and
/// tool activity into a workflow step result.
pub async fn WorkflowHarnessBridge::run_prompt_turn(
  self : WorkflowHarnessBridge,
  prompt~ : String,
  instructions? : String,
) -> WorkflowHarnessTurnResult {
  let text = Ref("")
  let reasoning = Ref("")
  let tool_inputs_started = Ref(0)
  let events = Ref(0)
  let control = self.session.do_prompt_turn(
    @harness.HarnessV1PromptTurnOptions::new(
      prompt=@harness.HarnessV1Prompt::text(prompt),
      emit=part => {
        events.val = events.val + 1
        match part {
          @harness.HarnessTextDelta(delta~, ..) => text.val = text.val + delta
          @harness.HarnessReasoningDelta(delta~, ..) =>
            reasoning.val = reasoning.val + delta
          @harness.HarnessToolInputStart(..) =>
            tool_inputs_started.val = tool_inputs_started.val + 1
          _ => ()
        }
      },
      instructions?=instructions.map(fn(text) { @harness.Text(text) }),
    ),
  )
  control.done()
  {
    text: text.val,
    reasoning: reasoning.val,
    tool_inputs_started: tool_inputs_started.val,
    events: events.val,
  }
}
