///|
/// Predicate that decides whether a tool-calling loop should stop after the
/// current step.
pub type StopCondition = async (Array[GenerateTextStep]) -> Bool

///|
/// Stop after exactly `step_count` completed steps.
pub fn is_step_count(step_count : Int) -> StopCondition {
  steps => steps.length() == step_count
}

///|
/// AI SDK-style camel-case spelling.
pub fn isStepCount(step_count : Int) -> StopCondition {
  is_step_count(step_count)
}

///|
/// Never stop a loop through an explicit condition.
pub fn is_loop_finished() -> StopCondition {
  _steps => false
}

///|
/// AI SDK-style camel-case spelling.
pub fn isLoopFinished() -> StopCondition {
  is_loop_finished()
}

///|
/// Stop when the latest step contains one of the named tool calls.
pub fn has_tool_call(tool_names : Array[String]) -> StopCondition {
  steps => {
    guard steps.length() > 0 else { return false }
    steps[steps.length() - 1].tool_calls.any(call => {
      tool_names.contains(call.tool_name)
    })
  }
}

///|
/// AI SDK-style camel-case spelling.
pub fn hasToolCall(tool_names : Array[String]) -> StopCondition {
  has_tool_call(tool_names)
}

///|
async fn stop_condition_met(
  conditions : Array[StopCondition],
  steps : Array[GenerateTextStep],
) -> Bool {
  let checks : Array[async () -> Bool] = []
  for condition in conditions {
    checks.push(() => condition(steps.copy()))
  }
  @async.all(checks).any(value => value)
}
