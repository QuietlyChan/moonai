///|
priv struct OpenAIBatchMockTransport {
  responses : Array[String]
  next : Ref[Int]
  requests : Array[@provider_utils.HttpRequest]
}

///|
fn OpenAIBatchMockTransport::new(
  responses : Array[String],
) -> OpenAIBatchMockTransport {
  { responses, next: Ref(0), requests: [], }
}

///|
impl @provider_utils.HttpTransport for OpenAIBatchMockTransport with fn fetch(
  self,
  request,
) {
  self.requests.push(request)
  guard self.next.val < self.responses.length() else {
    fail("unexpected OpenAI batch request")
  }
  let body = self.responses[self.next.val]
  self.next.val = self.next.val + 1
  @provider_utils.HttpResponse::text(status_code=200, body~)
}

///|
impl @provider_utils.HttpTransport for OpenAIBatchMockTransport with fn fetch_stream(
  _self,
  _request,
) {
  fail("OpenAI batch streaming transport was not expected")
}

///|
async test "OpenAI batch do_start uploads JSONL and submits the batch" {
  let transport = OpenAIBatchMockTransport::new([
    "{\"id\":\"file-batch-1\",\"object\":\"file\",\"status\":\"processed\"}", "{\"id\":\"batch_1\",\"object\":\"batch\",\"status\":\"in_progress\",\"request_counts\":{\"total\":1,\"pending\":1,\"completed\":0,\"failed\":0}}",
  ])
  let provider = create_openai(
    api_key="test-key",
    base_url="https://mock.openai.test/v1",
    http_transport=transport,
  )
  let started = @ai.start_batch(provider.batch(), requests=[
    @provider.BatchTextRequest({
      request_id: "req-1",
      model_id: "gpt-5-mini",
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
  assert_eq(started.batch_id, "batch_1")
  assert_true(started.status.state is @provider.BatchPending)
  // First request uploads the JSONL input file, second submits the batch.
  assert_eq(transport.requests.length(), 2)
  assert_true(transport.requests[0].url.contains("/v1/files"))
  let upload_body = transport.requests[0].body_text()
  assert_true(
    upload_body.contains("custom_id\": \"req-1") ||
    upload_body.contains("custom_id\":\"req-1"),
  )
  assert_true(transport.requests[1].url.contains("/v1/batches"))
  let submit_body = transport.requests[1].body_text()
  assert_true(submit_body.contains("\"input_file_id\":\"file-batch-1\""))
  assert_true(submit_body.contains("/v1/chat/completions"))
}

///|
async test "OpenAI batch do_get_batch_status maps lifecycle state" {
  let transport = OpenAIBatchMockTransport::new([
    "{\"id\":\"batch_1\",\"status\":\"completed\",\"request_counts\":{\"total\":2,\"pending\":0,\"completed\":2,\"failed\":0}}",
  ])
  let provider = create_openai(
    api_key="test-key",
    base_url="https://mock.openai.test/v1",
    http_transport=transport,
  )
  let status = @ai.get_batch_status(provider.batch(), batch_id="batch_1")
  assert_true(status.state is @provider.BatchCompleted)
  let counts = status.request_counts.unwrap()
  assert_eq(counts.completed, 2)
  assert_true(transport.requests[0].url.contains("/v1/batches/batch_1"))
}
