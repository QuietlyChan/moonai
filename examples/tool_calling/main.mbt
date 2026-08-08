///|
async fn main {
  let matches = @argparse.Command(
    "moonai-tool-calling",
    about="Run a multi-step MoonAI agent with executable MoonBit tools.",
    positionals=[
      @argparse.PositionArg("prompt", about="Agent task.", default_values=[
        "Calculate 42 * 8 and explain the result.",
      ]),
    ],
  ).parse()
  let prompt = match matches.values {
    { "prompt": [value], .. } => value
    _ => "Calculate 42 * 8 and explain the result."
  }
  let config = @shared.load_example_config()
  let tools = @shared.example_tools(sink=event => {
    @stdio.stdout.write("[runtime] " + event.stringify() + "\n")
  })
  @stdio.stdout.write(
    "MoonAI tool agent | provider=" +
    config.display_provider() +
    " | model=" +
    config.model_id() +
    "\nUser: " +
    prompt +
    "\n\n",
  )
  let result = @ai.stream_text(
    config.language_model(),
    prompt~,
    tools~,
    stop_when=[@ai.is_step_count(5)],
    on_event=event => {
      match event {
        @provider.V4ToolInputStart(id~, tool_name~, ..) =>
          @stdio.stdout.write(
            "[model] tool-call start " + tool_name + " (" + id + ")\n",
          )
        @provider.V4ToolInputDelta(id~, delta~, ..) =>
          @stdio.stdout.write("[model] tool input " + id + ": " + delta + "\n")
        @provider.V4ToolCallReady(call) =>
          @stdio.stdout.write(
            "[model] tool-call ready " + call.tool_name + "\n",
          )
        @provider.V4TextDelta(delta~, ..) => @stdio.stdout.write(delta)
        @provider.V4ReasoningDelta(delta~, ..) =>
          @stdio.stderr.write("[reasoning] " + delta)
        _ => ()
      }
    },
  ) catch {
    error => {
      @stdio.stdout.write("\nAgent failed: \{error}\n")
      return
    }
  }
  @stdio.stdout.write(
    "\n\nCompleted " +
    result.steps.length().to_string() +
    " step(s), " +
    result.tool_results.length().to_string() +
    " tool result(s).\n",
  )
  @stdio.stdout.write(
    "Usage: " + @shared.usage_json(result.total_usage).stringify() + "\n",
  )
}
