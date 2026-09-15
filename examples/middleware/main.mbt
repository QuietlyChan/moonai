///|
/// Middleware chain demo: wrap any model with reusable middlewares before
/// the call. Runs fully offline against the shared demo model.
async fn main {
  println("== MoonAI middleware demo (offline demo model) ==")
  let config = @shared.load_example_config()
  let demo = config.language_model()
  // 1. Default settings: fill model params on every call.
  let defaults_template = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([]),
    temperature=0.3,
  )
  let with_defaults = @model.default_settings_middleware(defaults_template)
  // 2. Extract reasoning: split interleaved <think> blocks into
  //    reasoning parts (mode defaults to_tag chaining).
  let with_reasoning = @model.extract_reasoning_middleware(
    mode=@model.ExtractStrip,
  )
  // 3. Simulate streaming for providers that only support generate.
  let simulated = @model.simulate_streaming_middleware()
  let wrapped = @model.wrap_language_model_v4_chain(
    demo,
    [with_defaults, with_reasoning, simulated],
    model_id=config.model_id(),
  )
  let result = @ai.generate_text(wrapped, prompt="Say hi in five words")
  println("finish: \{@debug.to_string(result.finish_reason)}")
  println("text: \{result.text()}")
}
