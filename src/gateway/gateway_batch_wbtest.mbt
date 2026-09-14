///|
test "gateway batch request encoding asserts a single text model" {
  let first : @provider.BatchV4TextRequest = {
    request_id: "req-1",
    model_id: "openai/gpt-5.2",
    prompt: "hello",
    max_output_tokens: None,
    temperature: None,
    top_p: None,
    top_k: None,
    presence_penalty: None,
    frequency_penalty: None,
    seed: None,
    stop_sequences: [],
    reasoning: @provider.V4ReasoningProviderDefault,
    response_format: @provider.V4ResponseText,
    tools: [],
    tool_choice: None,
    provider_options: Map([]),
  }
  let second : @provider.BatchV4TextRequest = {
    request_id: "req-2",
    model_id: "openai/gpt-5.2",
    prompt: "world",
    max_output_tokens: None,
    temperature: None,
    top_p: None,
    top_k: None,
    presence_penalty: None,
    frequency_penalty: None,
    seed: None,
    stop_sequences: [],
    reasoning: @provider.V4ReasoningProviderDefault,
    response_format: @provider.V4ResponseText,
    tools: [],
    tool_choice: None,
    provider_options: Map([]),
  }
  assert_eq(
    gateway_assert_text_batch([
      @provider.BatchTextRequest(first),
      @provider.BatchTextRequest(second),
    ]),
    "openai/gpt-5.2",
  )
}

///|
test "gateway batch idempotency key is extracted and omitted" {
  let gateway_options : Map[String, Json] = Map([
    ("idempotencyKey", Json::string("idem-1")),
    ("other", Json::string("x")),
  ])
  let (key, forwarded) = gateway_batch_idempotency(
    provider_options=Map([("gateway", Json::object(gateway_options))]),
  )
  assert_eq(key, Some("idem-1"))
  guard forwarded.get("gateway") is Some(Object(fields)) else {
    fail("expected forwarded gateway options")
  }
  assert_true(fields.get("idempotencyKey") is None)
  assert_eq(fields.get("other"), Some(Json::string("x")))
}
