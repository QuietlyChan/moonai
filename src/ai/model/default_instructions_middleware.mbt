///|
/// Default-instructions middleware.
///
/// Applies default instructions to a language model when a call does not
/// already contain a system message. Instructions can be plain text, a
/// single model message, or a list of messages; non-text message parts are
/// preserved through their text content.
pub fn default_instructions_middleware(
  instructions~ : @prompt.Instructions,
) -> @provider.LanguageModelV4Middleware {
  let default_system_messages : Array[@provider.LanguageModelV4Message] = match
    instructions {
    @prompt.InstructionText(text) =>
      [@provider.V4SystemMessage(content=text, provider_options=Map([]))]
    @prompt.InstructionMessage(message) =>
      [
        @provider.V4SystemMessage(
          content=message.content,
          provider_options=@provider.copy_provider_metadata(
            message.provider_options,
          ),
        ),
      ]
    @prompt.InstructionMessages(messages) =>
      [
        for message in messages => {
          @provider.V4SystemMessage(
            content=message.content,
            provider_options=@provider.copy_provider_metadata(
              message.provider_options,
            ),
          )
        }
      ]
  }
  @provider.LanguageModelV4Middleware::new(transform_params=fn(context) {
    let params = context.params
    if default_system_messages.length() == 0 {
      return params
    }
    let mut has_system = false
    for message in params.prompt.messages {
      if message is @provider.V4SystemMessage(_) {
        has_system = true
        break
      }
    }
    if has_system {
      return params
    }
    let messages : Array[@provider.LanguageModelV4Message] = []
    for message in default_system_messages {
      messages.push(message)
    }
    for message in params.prompt.messages {
      messages.push(message)
    }
    { ..params, prompt: @provider.LanguageModelV4Prompt::new(messages), }
  })
}
