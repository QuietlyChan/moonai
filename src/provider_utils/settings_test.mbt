///|
fn restore_test_environment_variable(name : String, previous : String?) -> Unit {
  match previous {
    Some(value) => @env.set_env_var(name, value)
    None => @env.unset_env_var(name)
  }
}

///|
test "explicit API key takes precedence over the environment" {
  let name = "MOONAI_TEST_EXPLICIT_API_KEY"
  let previous = @env.get_env_var(name)
  defer restore_test_environment_variable(name, previous)
  @env.set_env_var(name, "environment-key")
  assert_eq(
    load_api_key(
      "explicit-key",
      environment_variable_name=name,
      description="Test provider",
    ),
    "explicit-key",
  )
}

///|
test "API key falls back to the environment" {
  let name = "MOONAI_TEST_ENVIRONMENT_API_KEY"
  let previous = @env.get_env_var(name)
  defer restore_test_environment_variable(name, previous)
  @env.set_env_var(name, "environment-key")
  assert_eq(
    load_api_key(
      "",
      environment_variable_name=name,
      description="Test provider",
    ),
    "environment-key",
  )
}

///|
test "missing API key raises a typed provider error" {
  let name = "MOONAI_TEST_MISSING_API_KEY"
  let previous = @env.get_env_var(name)
  defer restore_test_environment_variable(name, previous)
  @env.unset_env_var(name)
  try
    load_api_key(
      "",
      environment_variable_name=name,
      api_key_parameter_name="token",
      description="Test provider",
    )
  catch {
    @provider.LoadAPIKeyError(
      environment_variable_name~,
      api_key_parameter_name~,
      description~,
      message~
    ) => {
      assert_eq(environment_variable_name, name)
      assert_eq(api_key_parameter_name, "token")
      assert_eq(description, "Test provider")
      assert_true(message.length() > 0)
    }
  } noraise {
    _ => fail("expected a missing API key error")
  }
}

///|
test "required and optional settings use the same precedence" {
  let name = "MOONAI_TEST_SETTING"
  let previous = @env.get_env_var(name)
  defer restore_test_environment_variable(name, previous)
  @env.set_env_var(name, "environment-value")
  assert_eq(
    load_setting(
      "explicit-value",
      environment_variable_name=name,
      setting_name="base_url",
      description="Test provider",
    ),
    "explicit-value",
  )
  assert_eq(
    load_setting(
      "",
      environment_variable_name=name,
      setting_name="base_url",
      description="Test provider",
    ),
    "environment-value",
  )
  assert_eq(
    load_optional_setting("", environment_variable_name=name),
    Some("environment-value"),
  )
  @env.unset_env_var(name)
  assert_eq(load_optional_setting("", environment_variable_name=name), None)
}
