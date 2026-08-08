///|
priv struct MiniMaxReasoningMockTransport {
  requests : Array[@provider_utils.HttpRequest]
}

///|
fn MiniMaxReasoningMockTransport::new() -> MiniMaxReasoningMockTransport {
  { requests: [] }
}

///|
impl @provider_utils.HttpTransport for MiniMaxReasoningMockTransport with fn fetch(
  self,
  request,
) {
  self.requests.push(request)
  @provider_utils.HttpResponse::text(
    status_code=200,
    body="{\"id\":\"msg_minimax_reasoning\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"Counting the letters...\",\"signature\":\"sig_123\"},{\"type\":\"text\",\"text\":\"There are 3 r characters.\",\"citations\":[{\"type\":\"web_search_result_location\",\"cited_text\":\"There are 3 r characters.\",\"url\":\"https://example.com\",\"title\":\"Example\",\"encrypted_index\":\"enc-1\"}]}],\"model\":\"minimax-m3\",\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":4,\"output_tokens\":30}}",
  )
}

///|
impl @provider_utils.HttpTransport for MiniMaxReasoningMockTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("streaming transport was not expected")
}

///|
async test "MiniMax forwards typed thinking options through Anthropic Messages" {
  let transport = MiniMaxReasoningMockTransport::new()
  let model = create_minimax(api_key="test-key", http_transport=transport, id_generator=() => {
    "minimax-source-id"
  }).chat("minimax-m3")
  let result = @ai.generate_text(
    model,
    prompt="Count the letter r.",
    provider_options=MiniMaxLanguageModelOptions::new(thinking=AdaptiveThinking).to_provider_options(),
    retry_policy=@provider.RetryPolicy::none(),
  )
  assert_eq(result.reasoning(), "Counting the letters...")
  assert_eq(result.text(), "There are 3 r characters.")
  assert_eq(result.usage.input_tokens.total, Some(4))
  assert_eq(result.usage.output_tokens.total, Some(30))
  assert_eq(result.finish_reason.raw, Some("end_turn"))
  assert_eq(result.sources.length(), 1)
  match result.sources[0] {
    @provider.V4UrlSource(id~, ..) => assert_eq(id, "minimax-source-id")
    _ => fail("expected MiniMax citation source")
  }
  assert_true(result.final_step.usage.raw is Some({ "output_tokens": 30, .. }))
  assert_eq(transport.requests.length(), 1)
  let request = transport.requests[0]
  assert_eq(request.url, "https://api.minimax.io/anthropic/v1/messages")
  assert_eq(request.headers.get("x-api-key"), Some("test-key"))
  json_inspect(@json.parse(request.body_text()), content={
    "model": "minimax-m3",
    "messages": [
      {
        "role": "user",
        "content": [{ "type": "text", "text": "Count the letter r." }],
      },
    ],
    "max_tokens": 4096,
    "thinking": { "type": "adaptive" },
  })
}

///|
async test "MiniMax uses MINIMAX_API_KEY for its Anthropic-compatible model" {
  let environment_name = "MINIMAX_API_KEY"
  let previous = @env.get_env_var(environment_name)
  defer (match previous {
    Some(value) => @env.set_env_var(environment_name, value)
    None => @env.unset_env_var(environment_name)
  })
  @env.set_env_var(environment_name, "environment-key")
  let transport = MiniMaxReasoningMockTransport::new()
  let model = create_minimax(http_transport=transport).chat("minimax-m3")
  let result = @ai.generate_text(
    model,
    prompt="Count the letter r.",
    retry_policy=@provider.RetryPolicy::none(),
  )
  assert_eq(result.text(), "There are 3 r characters.")
  assert_eq(
    transport.requests[0].headers.get("x-api-key"),
    Some("environment-key"),
  )
}
