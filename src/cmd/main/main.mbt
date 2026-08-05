///|
async fn main {
  guard @env.get_env_var("OPENAI_API_KEY") is Some(api_key) && api_key != "" else {
    println("OPENAI_API_KEY is required")
    return
  }
  let model = @openai.openai("gpt-4.1-mini", api_key~)
  let result = @ai.streamText(
    model,
    prompt="Explain MoonBit in three concise sentences.",
    on_event=event => {
      match event {
        @provider.V4TextDelta(delta~, ..) => @stdio.stdout.write(delta)
        _ => ()
      }
    },
  ) catch {
    error => {
      println("\nrequest failed: \{error}")
      return
    }
  }
  let input_tokens = result.usage.input_tokens.total.unwrap_or(0)
  let output_tokens = result.usage.output_tokens.total.unwrap_or(0)
  let total_tokens = input_tokens + output_tokens
  println("\n\nused \{total_tokens} tokens")
}
