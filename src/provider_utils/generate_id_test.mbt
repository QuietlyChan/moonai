///|
test "create_id_generator uses the requested random length" {
  let generator = create_id_generator(size=10)
  assert_eq(generator().length(), 10)
}

///|
test "create_id_generator adds a prefix and separator" {
  let generator = create_id_generator(
    prefix="tool",
    separator="_",
    size=8,
    alphabet="abc123",
  )
  let value = generator()
  assert_true(value.has_prefix("tool_"))
  assert_eq(value.length(), 13)
  assert_true(
    value[5:].to_owned().to_array().all(ch => "abc123".contains(ch.to_string())),
  )
}

///|
test "create_id_generator rejects a separator in the alphabet" {
  try create_id_generator(prefix="tool", separator="a", alphabet="abc") catch {
    @provider.InvalidArgumentError(argument~, message~) => {
      assert_eq(argument, "separator")
      assert_true(message.contains("separator"))
    }
  } noraise {
    _ => fail("expected an invalid separator error")
  }
}

///|
test "create_id_generator rejects invalid size and alphabet" {
  try create_id_generator(size=-1) catch {
    @provider.InvalidArgumentError(argument="size", ..) => ()
    @provider.InvalidArgumentError(..) => fail("unexpected argument name")
  } noraise {
    _ => fail("expected an invalid size error")
  }
  try create_id_generator(alphabet="") catch {
    @provider.InvalidArgumentError(argument="alphabet", ..) => ()
    @provider.InvalidArgumentError(..) => fail("unexpected argument name")
  } noraise {
    _ => fail("expected an invalid alphabet error")
  }
}

///|
test "generate_id produces distinct identifiers across calls" {
  let first = generate_id()
  let second = generate_id()
  assert_eq(first.length(), 16)
  assert_eq(second.length(), 16)
  assert_true(first != second)
}
