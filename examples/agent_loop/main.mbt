///|
/// Tool-loop agent demo: the shared demo model deterministically picks the
/// `calculator` tool on the first step and answers on the second, exercising
/// the full agent tool loop offline. Set MOONAI_PROVIDER/MODEL/KEY to run
/// against a live model instead.
async fn main {
  println("== MoonAI tool-loop agent demo ==")
  let config = @shared.load_example_config()
  let agent = @agent.ToolLoopAgent::new(
    settings=@agent.ToolLoopAgentSettings::new(
      model=config.language_model(),
      id="moonai-demo-agent",
      instructions=@prompt.Instructions::text(
        "Answer math questions using the calculator tool.",
      ),
      tools=@shared.example_tools(),
    ),
  )
  let result = (agent as &@agent.Agent).generate(
    @agent.AgentCallOptions::new(prompt="What is (6 * 7) + 2?"),
  )
  println("tool results: \{result.tool_results.length()}")
  println("text: \{result.text()}")
}
