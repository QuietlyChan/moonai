///|
priv struct OpenAIFactoryMockTransport {
  requests : Array[@provider_utils.HttpRequest]
}

///|
fn OpenAIFactoryMockTransport::new() -> OpenAIFactoryMockTransport {
  { requests: [] }
}

///|
impl @provider_utils.HttpTransport for OpenAIFactoryMockTransport with fn fetch(
  self,
  request,
) {
  self.requests.push(request)
  @provider_utils.HttpResponse::text(
    status_code=200,
    body="{\"data\":[{\"index\":0,\"embedding\":[0.25,0.5]}],\"usage\":{\"prompt_tokens\":1}}",
    headers={ "x-request-id": "mock-request" },
  )
}

///|
impl @provider_utils.HttpTransport for OpenAIFactoryMockTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("streaming transport was not expected")
}

///|
async test "OpenAI provider propagates its injected HTTP transport" {
  let transport = OpenAIFactoryMockTransport::new()
  let provider = create_openai(
    api_key="test-key",
    base_url="https://mock.openai.test/v1",
    http_transport=transport,
  )
  let result = @ai.embed(
    provider.embedding("text-embedding-3-small"),
    "MoonBit",
    retry_policy=@provider.RetryPolicy::none(),
  )
  assert_eq(result.embedding, [0.25, 0.5])
  assert_eq(result.usage.input_tokens, 1)
  assert_eq(
    result.response.unwrap().headers.get("x-request-id"),
    Some("mock-request"),
  )
  assert_eq(transport.requests.length(), 1)
  let request = transport.requests[0]
  assert_eq(request.meth, @provider_utils.HttpPost)
  assert_eq(request.url, "https://mock.openai.test/v1/embeddings")
  assert_eq(request.headers.get("Authorization"), Some("Bearer test-key"))
  json_inspect(@json.parse(request.body_text()), content={
    "model": "text-embedding-3-small",
    "input": ["MoonBit"],
    "encoding_format": "float",
  })
}

///|
async test "OpenAI provider loads its API key from the environment" {
  let environment_name = "OPENAI_API_KEY"
  let previous = @env.get_env_var(environment_name)
  defer (match previous {
    Some(value) => @env.set_env_var(environment_name, value)
    None => @env.unset_env_var(environment_name)
  })
  @env.set_env_var(environment_name, "environment-key")
  let transport = OpenAIFactoryMockTransport::new()
  let provider = create_openai(
    base_url="https://mock.openai.test/v1",
    http_transport=transport,
  )
  let result = @ai.embed(
    provider.embedding("text-embedding-3-small"),
    "MoonBit",
    retry_policy=@provider.RetryPolicy::none(),
  )
  assert_eq(result.embedding, [0.25, 0.5])
  assert_eq(
    transport.requests[0].headers.get("Authorization"),
    Some("Bearer environment-key"),
  )
}
