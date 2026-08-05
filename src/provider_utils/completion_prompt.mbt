///|
/// Text prompt and provider-required stop sequences produced from a V4 prompt
/// for an OpenAI-style `/completions` endpoint.
pub(all) struct CompletionPrompt {
  prompt : String
  stop_sequences : Array[String]
} derive(Debug, Eq)

///|
/// Convert the provider-neutral V4 prompt into the labelled transcript used
/// by OpenAI-style completion models.
///
/// Completion endpoints cannot represent tool messages or assistant tool
/// calls. Other non-text content is ignored in the same way as AI SDK's
/// OpenAI and OpenAI-compatible completion converters.
pub fn convert_to_completion_prompt(
  prompt : @provider.LanguageModelV4Prompt,
  user? : String = "user",
  assistant? : String = "assistant",
) -> CompletionPrompt raise {
  let text = StringBuilder::new()
  let mut start = 0
  if prompt.messages.length() > 0 {
    match prompt.messages[0] {
      @provider.V4SystemMessage(content~, ..) => {
        text.write_string(content)
        text.write_string("\n\n")
        start = 1
      }
      _ => ()
    }
  }
  for index = start; index < prompt.messages.length(); index = index + 1 {
    match prompt.messages[index] {
      @provider.V4SystemMessage(content~, ..) =>
        raise @provider.InvalidPromptError(
          message="Unexpected system message in prompt: \{content}",
        )
      @provider.V4UserMessage(content~, ..) => {
        text.write_string(user)
        text.write_string(":\n")
        for part in content {
          match part {
            @provider.V4PromptText(text=value, ..) => text.write_string(value)
            _ => ()
          }
        }
        text.write_string("\n\n")
      }
      @provider.V4AssistantMessage(content~, ..) => {
        text.write_string(assistant)
        text.write_string(":\n")
        for part in content {
          match part {
            @provider.V4PromptText(text=value, ..) => text.write_string(value)
            @provider.V4PromptToolCall(_) =>
              raise @provider.UnsupportedFunctionalityError(
                functionality="tool-call messages",
              )
            _ => ()
          }
        }
        text.write_string("\n\n")
      }
      @provider.V4ToolMessage(..) =>
        raise @provider.UnsupportedFunctionalityError(
          functionality="tool messages",
        )
    }
  }
  text.write_string(assistant)
  text.write_string(":\n")
  { prompt: text.to_string(), stop_sequences: ["\n\{user}:"] }
}
