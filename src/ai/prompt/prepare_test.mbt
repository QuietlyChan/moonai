///|
test "standardize prompt converts a string to one user message" {
  let standardized = standardize_prompt(Some("hello"), [])
  assert_eq(standardized.instructions, None)
  assert_eq(standardized.messages, [@provider_utils.ModelMessage::user("hello")])
}

///|
test "standardize prompt copies an explicit message list" {
  let source = [@provider_utils.ModelMessage::user("hello")]
  let standardized = standardize_prompt(None, source)
  standardized.messages.push(@provider_utils.ModelMessage::assistant("world"))
  assert_eq(source, [@provider_utils.ModelMessage::user("hello")])
}

///|
test "standardize prompt rejects prompt and messages together" {
  try
    standardize_prompt(Some("hello"), [
      @provider_utils.ModelMessage::user("world"),
    ])
  catch {
    @provider.InvalidPromptError(message~) =>
      assert_true(
        message.contains(
          "prompt and messages cannot be defined at the same time",
        ),
      )
    error => fail("unexpected prompt validation error: \{error}")
  } noraise {
    _ => fail("expected prompt input validation to fail")
  }
}

///|
test "standardize prompt rejects an empty input" {
  try standardize_prompt(None, []) catch {
    @provider.InvalidPromptError(message~) =>
      assert_true(message.contains("prompt or messages must be defined"))
    error => fail("unexpected empty prompt error: \{error}")
  } noraise {
    _ => fail("expected empty prompt validation to fail")
  }
}

///|
test "language model call options require a positive output token limit" {
  let invalid = LanguageModelCallOptions::new(max_output_tokens=0)
  try prepare_language_model_call_options(invalid) catch {
    @provider.InvalidArgumentError(argument~, message~) => {
      assert_eq(argument, "max_output_tokens")
      assert_true(
        message.contains("max_output_tokens must be greater than or equal to 1"),
      )
    }
    error => fail("unexpected call settings error: \{error}")
  } noraise {
    _ => fail("expected output token validation to fail")
  }
}

///|
test "language model call options isolate mutable stop sequences" {
  let source = ["END"]
  let prepared = prepare_language_model_call_options(
    LanguageModelCallOptions::new(
      max_output_tokens=128,
      stop_sequences=source,
      reasoning_effort=@provider.High,
    ),
  )
  prepared.stop_sequences.push("STOP")
  assert_eq(source, ["END"])
  assert_eq(prepared.max_output_tokens, Some(128))
  assert_eq(prepared.reasoning_effort, @provider.High)
}
