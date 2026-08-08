///|
async fn main {
  let matches = @argparse.Command(
    "moonai-basic-chat",
    about="Stream one response through MoonAI's provider-neutral API.",
    positionals=[
      @argparse.PositionArg(
        "prompt",
        about="Prompt sent to the configured language model.",
        default_values=["What can I build with MoonAI?"],
      ),
    ],
  ).parse()
  let prompt = match matches.values {
    { "prompt": [value], .. } => value
    _ => "What can I build with MoonAI?"
  }
  let config = @shared.load_example_config()
  @stdio.stdout.write(
    "MoonAI basic chat | provider=" +
    config.display_provider() +
    " | model=" +
    config.model_id() +
    "\n\nAssistant: ",
  )
  let result = @ai.stream_text(config.language_model(), prompt~, on_event=event => {
    match event {
      @provider.V4TextDelta(delta~, ..) => @stdio.stdout.write(delta)
      @provider.V4ReasoningDelta(delta~, ..) =>
        @stdio.stderr.write("[reasoning] " + delta)
      _ => ()
    }
  }) catch {
    error => {
      @stdio.stdout.write("\nRequest failed: \{error}\n")
      return
    }
  }
  @stdio.stdout.write(
    "\n\nUsage: " + @shared.usage_json(result.total_usage).stringify() + "\n",
  )
}
