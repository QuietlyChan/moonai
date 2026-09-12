///|
priv struct AnthropicBatchMockTransport {
  responses : Array[String]
  next : Ref[Int]
  requests : Array[@provider_utils.HttpRequest]
}

///|
fn AnthropicBatchMockTransport::new(
  responses : Array[String],
) -> AnthropicBatchMockTransport {
  { responses, next: Ref(0), requests: [], }
}

///|
impl @provider_utils.HttpTransport for AnthropicBatchMockTransport with fn fetch(
  self,
  request,
) {
  self.requests.push(request)
  guard self.next.val < self.responses.length() else {
    fail("unexpected Anthropic batch request")
  }
  let body = self.responses[self.next.val]
  self.next.val = self.next.val + 1
  @provider_utils.HttpResponse::text(status_code=200, body~)
}

///|
impl @provider_utils.HttpTransport for AnthropicBatchMockTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("Anthropic batch streaming transport was not expected")
}

///|
async test "Anthropic batch do_start submits prepared message requests" {
  let transport = AnthropicBatchMockTransport::new([
    "{\"id\":\"msgbatch_1\",\"processing_status\":\"in_progress\",\"request_counts\":{\"processing\":1,\"succeeded\":0,\"errored\":0,\"canceled\":0,\"expired\":0}}",
  ])
  let provider = create_anthropic(
    api_key="test-key",
    base_url="https://mock.anthropic.test",
    http_transport=transport,
    id_generator=() => "generated-id",
  )
  let started = @ai.start_batch(provider.batch(), requests=[
    @provider.BatchTextRequest({
      request_id: "req-1",
      model_id: "claude-sonnet-4-5",
      prompt: "Say hello",
      max_output_tokens: Some(64),
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
    }),
  ])
  assert_eq(started.batch_id, "msgbatch_1")
  assert_true(started.status.state is @provider.BatchPending)
  assert_eq(transport.requests.length(), 1)
  assert_true(transport.requests[0].url.contains("/v1/messages/batches"))
  let request_body = transport.requests[0].body_text()
  assert_true(request_body.contains("\"custom_id\":\"req-1\""))
  assert_true(request_body.contains("\"model\":\"claude-sonnet-4-5\""))
  assert_true(request_body.contains("Say hello"))
}

///|
async test "Anthropic batch status maps processing counts and state" {
  let transport = AnthropicBatchMockTransport::new([
    "{\"id\":\"msgbatch_1\",\"processing_status\":\"ended\",\"request_counts\":{\"processing\":0,\"succeeded\":2,\"errored\":0,\"canceled\":0,\"expired\":0},\"created_at\":\"2026-09-12T00:00:00Z\",\"expires_at\":\"2026-09-13T00:00:00Z\",\"results_url\":\"/v1/messages/batches/msgbatch_1/results\"}",
  ])
  let provider = create_anthropic(
    api_key="test-key",
    base_url="https://mock.anthropic.test",
    http_transport=transport,
    id_generator=() => "generated-id",
  )
  let status = @ai.get_batch_status(provider.batch(), batch_id="msgbatch_1")
  assert_true(status.state is @provider.BatchCompleted)
  assert_eq(status.raw_status, Some("ended"))
  let counts = status.request_counts.unwrap()
  assert_eq(counts.completed, 2)
  assert_eq(counts.pending, 0)
  assert_true(
    transport.requests[0].url.contains("/v1/messages/batches/msgbatch_1"),
  )
}

///|
async test "Anthropic batch results decode succeeded and errored lines" {
  let transport = AnthropicBatchMockTransport::new([
    "{\"id\":\"msgbatch_1\",\"processing_status\":\"ended\",\"request_counts\":{\"processing\":0,\"succeeded\":1,\"errored\":1,\"canceled\":0,\"expired\":0},\"results_url\":\"/v1/messages/batches/msgbatch_1/results\"}",
    "{\"custom_id\":\"req-ok\",\"result\":{\"type\":\"succeeded\",\"message\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-sonnet-4-5\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":3,\"output_tokens\":2}}}}\n{\"custom_id\":\"req-bad\",\"result\":{\"type\":\"errored\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"boom\"}}}",
  ])
  let provider = create_anthropic(
    api_key="test-key",
    base_url="https://mock.anthropic.test",
    http_transport=transport,
    id_generator=() => "generated-id",
  )
  let results = @ai.get_batch_results(provider.batch(), batch_id="msgbatch_1")
  assert_eq(results.length(), 2)
  match results[0] {
    @provider.BatchItemSucceeded(
      id~,
      result=@provider.BatchTextResult(text),
      ..
    ) => {
      assert_eq(id, "req-ok")
      assert_eq(text.content.length(), 1)
    }
    _ => fail("expected a succeeded item result")
  }
  assert_true(results[1] is @provider.BatchItemFailed(id="req-bad", ..))
}
