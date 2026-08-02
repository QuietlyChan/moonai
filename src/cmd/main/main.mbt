///|
async fn main {
  guard @env.get_env_var("OPENAI_API_KEY") is Some(api_key) && api_key != "" else {
    println("OPENAI_API_KEY is required")
    return
  }
  let model = @openai.openai("gpt-4.1-mini", api_key~)
  let result = @moonai.streamText(
    model,
    prompt="Explain MoonBit in three concise sentences.",
    on_event=event => {
      match event {
        @moonai.TextDelta(delta~, ..) => @stdio.stdout.write(delta)
        _ => ()
      }
    },
  ) catch {
    error => {
      println("\nrequest failed: \{error}")
      return
    }
  }
  println("\n\nused \{result.usage.total_tokens} tokens")
}
