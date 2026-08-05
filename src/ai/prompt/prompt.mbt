///|
/// The two input shapes accepted by a high-level generation call.
pub(all) enum PromptInput {
  Text(String)
  Messages(Array[@provider_utils.ModelMessage])
} derive(Debug)

///|
/// System instructions accepted by high-level AI calls.
///
/// This mirrors AI SDK's `Instructions` union without converting it into a
/// provider prompt prematurely.
pub(all) enum Instructions {
  InstructionText(String)
  InstructionMessage(@provider_utils.ModelMessage)
  InstructionMessages(Array[@provider_utils.ModelMessage])
} derive(Debug, Eq)

///|
/// Provider-neutral high-level prompt definition.
pub(all) struct Prompt {
  input : PromptInput
  instructions : Instructions?
  allow_system_in_messages : Bool
} derive(Debug)

///|
/// Prompt after input-shape and role validation, before provider conversion.
pub(all) struct StandardizedPrompt {
  instructions : Instructions?
  messages : Array[@provider_utils.ModelMessage]
} derive(Debug)

///|
fn copy_model_messages(
  messages : Array[@provider_utils.ModelMessage],
) -> Array[@provider_utils.ModelMessage] {
  [
    for message in messages => message.copy()
  ]
}

///|
fn validate_instructions(
  instructions : Array[@provider_utils.ModelMessage],
) -> Unit raise @provider.InvalidPromptError {
  for message in instructions {
    match message.role {
      @provider_utils.ModelSystem => ()
      _ =>
        raise @provider.InvalidPromptError(
          message="instructions must contain only system messages",
        )
    }
  }
}

///|
fn copy_instructions(instructions : Instructions) -> Instructions {
  match instructions {
    InstructionText(value) => InstructionText(value)
    InstructionMessage(value) => InstructionMessage(value.copy())
    InstructionMessages(values) =>
      InstructionMessages(copy_model_messages(values))
  }
}

///|
/// Construct text instructions.
pub fn Instructions::text(value : String) -> Instructions {
  InstructionText(value)
}

///|
/// Construct instructions from one system message.
pub fn Instructions::message(
  value : @provider_utils.ModelMessage,
) -> Instructions raise @provider.InvalidPromptError {
  validate_instructions([value])
  InstructionMessage(value.copy())
}

///|
/// Construct instructions from system messages and isolate the input array.
pub fn Instructions::messages(
  values : Array[@provider_utils.ModelMessage],
) -> Instructions raise @provider.InvalidPromptError {
  validate_instructions(values)
  InstructionMessages(copy_model_messages(values))
}

///|
/// Normalize instructions into user-facing system messages.
pub fn Instructions::as_messages(
  self : Instructions,
) -> Array[@provider_utils.ModelMessage] raise @provider.InvalidPromptError {
  let messages = match self {
    InstructionText(value) => [@provider_utils.ModelMessage::system(value)]
    InstructionMessage(value) => [value.copy()]
    InstructionMessages(values) => copy_model_messages(values)
  }
  validate_instructions(messages)
  messages
}

///|
fn normalize_instructions(
  instructions : Instructions?,
) -> Instructions? raise @provider.InvalidPromptError {
  match instructions {
    Some(value) => {
      ignore(value.as_messages())
      Some(copy_instructions(value))
    }
    None => None
  }
}

///|
/// Construct a prompt from an input value and optional system instructions.
pub fn Prompt::new(
  input : PromptInput,
  instructions? : Instructions,
  allow_system_in_messages? : Bool = false,
) -> Prompt raise {
  {
    input,
    instructions: normalize_instructions(instructions),
    allow_system_in_messages,
  }
}

///|
/// Construct a text prompt.
pub fn Prompt::text(
  value : String,
  instructions? : Instructions,
  allow_system_in_messages? : Bool = false,
) -> Prompt raise {
  Prompt::new(
    PromptInput::Text(value),
    instructions?,
    allow_system_in_messages~,
  )
}

///|
/// Construct a message prompt.
pub fn Prompt::messages(
  value : Array[@provider_utils.ModelMessage],
  instructions? : Instructions,
  allow_system_in_messages? : Bool = false,
) -> Prompt raise {
  Prompt::new(
    PromptInput::Messages(copy_model_messages(value)),
    instructions?,
    allow_system_in_messages~,
  )
}

///|
/// Return a copy with new instructions.
pub fn Prompt::with_instructions(
  self : Prompt,
  instructions : Instructions,
) -> Prompt raise {
  Prompt::new(
    self.input,
    instructions~,
    allow_system_in_messages=self.allow_system_in_messages,
  )
}

///|
/// Normalize the prompt into instructions and user-facing model messages.
pub fn Prompt::standardize(self : Prompt) -> StandardizedPrompt raise {
  let messages = match self.input {
    Text(value) => [@provider_utils.ModelMessage::user(value)]
    Messages(values) => copy_model_messages(values)
  }
  guard messages.length() > 0 else {
    raise @provider.InvalidPromptError(message="messages must not be empty")
  }
  if !self.allow_system_in_messages {
    for message in messages {
      match message.role {
        @provider_utils.ModelSystem =>
          raise @provider.InvalidPromptError(
            message="system messages are not allowed in prompt messages; use instructions",
          )
        _ => ()
      }
    }
  }
  {
    instructions: match self.instructions {
      Some(value) => Some(copy_instructions(value))
      None => None
    },
    messages,
  }
}

///|
/// Standardize the mutually exclusive `prompt` and `messages` forms.
pub fn standardize_prompt(
  prompt : String?,
  messages : Array[@provider_utils.ModelMessage],
  instructions? : Instructions,
  allow_system_in_messages? : Bool = false,
) -> StandardizedPrompt raise {
  let input = match prompt {
    Some(value) => {
      guard messages.length() == 0 else {
        raise @provider.InvalidPromptError(
          message="prompt and messages cannot be defined at the same time",
        )
      }
      PromptInput::Text(value)
    }
    None => {
      guard messages.length() > 0 else {
        raise @provider.InvalidPromptError(
          message="prompt or messages must be defined",
        )
      }
      PromptInput::Messages(copy_model_messages(messages))
    }
  }
  Prompt::new(input, instructions?, allow_system_in_messages~).standardize()
}

///|
/// AI SDK-style camel-case spelling for `standardize_prompt`.
pub fn standardizePrompt(
  prompt : String?,
  messages : Array[@provider_utils.ModelMessage],
  instructions? : Instructions,
  allow_system_in_messages? : Bool = false,
) -> StandardizedPrompt raise {
  standardize_prompt(prompt, messages, instructions?, allow_system_in_messages~)
}
