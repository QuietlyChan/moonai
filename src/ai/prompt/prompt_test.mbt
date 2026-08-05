///|
test "text prompts standardize into a user-facing message" {
  let prompt = Prompt::text("hello")
  let standardized = prompt.standardize()
  assert_eq(standardized.instructions, None)
  assert_eq(standardized.messages, [@provider_utils.ModelMessage::user("hello")])
}

///|
test "message prompts preserve instructions and copy input arrays" {
  let messages = [@provider_utils.ModelMessage::user("hello")]
  let instructions = [@provider_utils.ModelMessage::system("be concise")]
  let prompt = Prompt::messages(
    messages,
    instructions=Instructions::messages(instructions),
  )
  messages.push(@provider_utils.ModelMessage::assistant("mutated"))
  instructions.push(@provider_utils.ModelMessage::system("mutated"))
  let standardized = prompt.standardize()
  assert_eq(standardized.messages.length(), 1)
  guard standardized.instructions is Some(value) else {
    fail("expected standardized instructions")
  }
  assert_eq(value.as_messages(), [
    @provider_utils.ModelMessage::system("be concise"),
  ])
}

///|
test "prompt rejects non-system instructions" {
  try
    Prompt::text(
      "hello",
      instructions=InstructionMessage(@provider_utils.ModelMessage::user("bad")),
    )
  catch {
    @provider.InvalidPromptError(message~) =>
      assert_true(message.contains("instructions must contain only system"))
    error => fail("unexpected prompt error: \{error}")
  } noraise {
    _ => fail("expected invalid instructions to fail")
  }
}

///|
test "prompt rejects system messages by default" {
  let prompt = Prompt::messages([@provider_utils.ModelMessage::system("bad")])
  try prompt.standardize() catch {
    @provider.InvalidPromptError(message~) =>
      assert_true(message.contains("system messages are not allowed"))
    error => fail("unexpected prompt error: \{error}")
  } noraise {
    _ => fail("expected system message validation to fail")
  }
}

///|
test "prompt arguments use the explicit standardization boundary" {
  let standardized = standardize_prompt(
    Some("hello"),
    [],
    instructions=Instructions::text("context"),
  )
  guard standardized.instructions is Some(value) else {
    fail("expected text instructions")
  }
  assert_eq(value.as_messages(), [
    @provider_utils.ModelMessage::system("context"),
  ])
  assert_eq(
    standardized.messages[0],
    @provider_utils.ModelMessage::user("hello"),
  )
}
