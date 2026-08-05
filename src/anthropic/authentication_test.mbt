///|
priv struct AnthropicAuthenticationMockTransport {
  requests : Array[@provider_utils.HttpRequest]
}

///|
fn AnthropicAuthenticationMockTransport::new() -> AnthropicAuthenticationMockTransport {
  { requests: [] }
}

///|
impl @provider_utils.HttpTransport for AnthropicAuthenticationMockTransport with fn fetch(
  self,
  request,
) {
  self.requests.push(request)
  @provider_utils.HttpResponse::text(
    status_code=200,
    body="{\"id\":\"msg_env\",\"model\":\"claude-test\",\"content\":[{\"type\":\"text\",\"text\":\"ok\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}",
  )
}

///|
impl @provider_utils.HttpTransport for AnthropicAuthenticationMockTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("streaming transport was not expected")
}

///|
async test "Anthropic loads its API key from the environment" {
  let environment_name = "ANTHROPIC_API_KEY"
  let previous = @env.get_env_var(environment_name)
  defer (match previous {
    Some(value) => @env.set_env_var(environment_name, value)
    None => @env.unset_env_var(environment_name)
  })
  @env.set_env_var(environment_name, "environment-key")
  let transport = AnthropicAuthenticationMockTransport::new()
  let model = AnthropicLanguageModelV4::new(
      create_anthropic(
        base_url="https://mock.anthropic.test/v1",
        http_transport=transport,
      ).messages_wire("claude-test"),
    )
    as &@provider.LanguageModelV4
  let response = @ai.generate_text(
    model,
    prompt="hello",
    retry_policy=@provider.RetryPolicy::none(),
  )
  assert_eq(response.text(), "ok")
  assert_eq(
    transport.requests[0].headers.get("x-api-key"),
    Some("environment-key"),
  )
}

///|
test "Anthropic rejects two explicit authentication methods" {
  try create_anthropic(api_key="api-key", auth_token="auth-token") catch {
    @provider.InvalidArgumentError(argument~, message~) => {
      assert_eq(argument, "api_key/auth_token")
      assert_true(message.length() > 0)
    }
    _ => fail("unexpected Anthropic authentication error")
  } noraise {
    _ => fail("expected an Anthropic authentication error")
  }
}
