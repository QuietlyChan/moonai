///|
test "compatible provider credential setting applies to every model family" {
  let environment_name = "MOONAI_OPENAI_COMPATIBLE_TEST_KEY"
  let previous = @env.get_env_var(environment_name)
  defer (match previous {
    Some(value) => @env.set_env_var(environment_name, value)
    None => @env.unset_env_var(environment_name)
  })
  @env.set_env_var(environment_name, "environment-key")
  let provider = create_openai_compatible(
    provider_name="local-test",
    base_url="https://example.com/v1",
    api_key_environment_variable=environment_name,
  )
  let expected = Some("Bearer environment-key")
  assert_eq(
    provider
    .chat_language_model("chat")
    .request_headers_with(Map([]))
    .get("Authorization"),
    expected,
  )
  assert_eq(
    provider
    .completion_language_model("completion")
    .request_headers_with(Map([]))
    .get("Authorization"),
    expected,
  )
  assert_eq(
    provider
    .embedding_model_value("embedding")
    .request_headers()
    .get("Authorization"),
    expected,
  )
  assert_eq(
    provider.image_model_value("image").request_headers().get("Authorization"),
    expected,
  )
}
