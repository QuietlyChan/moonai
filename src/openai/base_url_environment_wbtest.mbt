///|
fn restore_openai_base_url(previous : String?) -> Unit {
  match previous {
    Some(value) => @env.set_env_var("OPENAI_BASE_URL", value)
    None => @env.unset_env_var("OPENAI_BASE_URL")
  }
}

///|
test "OpenAI base URL uses the official default when unset" {
  let previous = @env.get_env_var("OPENAI_BASE_URL")
  defer restore_openai_base_url(previous)
  @env.unset_env_var("OPENAI_BASE_URL")
  let provider = create_openai(api_key="test-key")
  assert_eq(provider.base_url, "https://api.openai.com/v1")
}

///|
test "OpenAI base URL reads OPENAI_BASE_URL and removes its trailing slash" {
  let previous = @env.get_env_var("OPENAI_BASE_URL")
  defer restore_openai_base_url(previous)
  @env.set_env_var("OPENAI_BASE_URL", "https://proxy.openai.example/v1/")
  let provider = create_openai(api_key="test-key")
  assert_eq(provider.base_url, "https://proxy.openai.example/v1")
}

///|
test "OpenAI base URL prefers an explicit value over OPENAI_BASE_URL" {
  let previous = @env.get_env_var("OPENAI_BASE_URL")
  defer restore_openai_base_url(previous)
  @env.set_env_var("OPENAI_BASE_URL", "https://env.openai.example/v1")
  let provider = create_openai(
    api_key="test-key",
    base_url="https://option.openai.example/v1/",
  )
  assert_eq(provider.base_url, "https://option.openai.example/v1")
}

///|
test "OpenAI rejects an explicitly empty base URL" {
  let previous = @env.get_env_var("OPENAI_BASE_URL")
  defer restore_openai_base_url(previous)
  @env.set_env_var("OPENAI_BASE_URL", "https://env.openai.example/v1")
  try create_openai(api_key="test-key", base_url="") catch {
    @provider.InvalidArgumentError(argument~, message~) => {
      assert_eq(argument, "baseURL")
      assert_eq(message, "baseURL must be a non-empty string.")
    }
  } noraise {
    _ => fail("expected an invalid base URL error")
  }
}
