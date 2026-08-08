///|
fn restore_anthropic_base_url(previous : String?) -> Unit {
  match previous {
    Some(value) => @env.set_env_var("ANTHROPIC_BASE_URL", value)
    None => @env.unset_env_var("ANTHROPIC_BASE_URL")
  }
}

///|
test "Anthropic base URL uses the versioned official default when unset" {
  let previous = @env.get_env_var("ANTHROPIC_BASE_URL")
  defer restore_anthropic_base_url(previous)
  @env.unset_env_var("ANTHROPIC_BASE_URL")
  let provider = create_anthropic(api_key="test-key")
  assert_eq(provider.base_url, "https://api.anthropic.com/v1")
}

///|
test "Anthropic base URL normalizes the bare official environment URL" {
  let previous = @env.get_env_var("ANTHROPIC_BASE_URL")
  defer restore_anthropic_base_url(previous)
  @env.set_env_var("ANTHROPIC_BASE_URL", "https://api.anthropic.com/")
  let provider = create_anthropic(api_key="test-key")
  assert_eq(provider.base_url, "https://api.anthropic.com/v1")
}

///|
test "Anthropic base URL prefers an explicit value over the environment" {
  let previous = @env.get_env_var("ANTHROPIC_BASE_URL")
  defer restore_anthropic_base_url(previous)
  @env.set_env_var("ANTHROPIC_BASE_URL", "https://env.anthropic.example/v1")
  let provider = create_anthropic(
    api_key="test-key",
    base_url="https://option.anthropic.example/v1/",
  )
  assert_eq(provider.base_url, "https://option.anthropic.example/v1")
}

///|
test "Anthropic Files uses the same base URL resolution boundary" {
  let previous = @env.get_env_var("ANTHROPIC_BASE_URL")
  defer restore_anthropic_base_url(previous)
  @env.set_env_var("ANTHROPIC_BASE_URL", "https://proxy.anthropic.example/v1/")
  let files = anthropic_files(api_key="test-key")
  assert_eq(files.base_url, "https://proxy.anthropic.example/v1")
}

///|
test "Anthropic rejects an explicitly blank base URL" {
  let previous = @env.get_env_var("ANTHROPIC_BASE_URL")
  defer restore_anthropic_base_url(previous)
  @env.set_env_var("ANTHROPIC_BASE_URL", "https://env.anthropic.example/v1")
  try create_anthropic(api_key="test-key", base_url="   ") catch {
    @provider.InvalidArgumentError(argument~, message~) => {
      assert_eq(argument, "baseURL")
      assert_eq(message, "baseURL must be a non-empty string.")
    }
    _ => fail("unexpected base URL error")
  } noraise {
    _ => fail("expected an invalid base URL error")
  }
}
