///|
priv struct DeepSeekMockStream {
  status : Int
  response_headers : Map[String, String]
  chunks : Array[String]
  next_chunk : Ref[Int]
}

///|
fn DeepSeekMockStream::new(
  chunks : Array[String],
  status? : Int = 200,
  headers? : Map[String, String] = Map([]),
) -> DeepSeekMockStream {
  {
    status,
    response_headers: @provider_utils.copy_headers(headers),
    chunks,
    next_chunk: Ref(0),
  }
}

///|
impl @provider_utils.HttpStreamResponse for DeepSeekMockStream with fn status_code(
  self,
) -> Int {
  self.status
}

///|
impl @provider_utils.HttpStreamResponse for DeepSeekMockStream with fn reason(
  _self,
) -> String {
  "OK"
}

///|
impl @provider_utils.HttpStreamResponse for DeepSeekMockStream with fn headers(
  self,
) -> Map[String, String] {
  @provider_utils.copy_headers(self.response_headers)
}

///|
impl @provider_utils.HttpStreamResponse for DeepSeekMockStream with fn read_until(
  self,
  _separator,
) -> String? {
  guard self.next_chunk.val < self.chunks.length() else { return None }
  let chunk = self.chunks[self.next_chunk.val]
  self.next_chunk.val = self.next_chunk.val + 1
  Some(chunk)
}

///|
impl @provider_utils.HttpStreamResponse for DeepSeekMockStream with fn read_all(
  self,
) -> Bytes {
  let remaining : Array[String] = []
  while self.next_chunk.val < self.chunks.length() {
    remaining.push(self.chunks[self.next_chunk.val])
    self.next_chunk.val = self.next_chunk.val + 1
  }
  @utf8.encode(remaining.join("\n"))
}

///|
impl @provider_utils.HttpStreamResponse for DeepSeekMockStream with fn close(
  _self,
) -> Unit {
  ()
}

///|
priv struct DeepSeekMockTransport {
  buffered_response : @provider_utils.HttpResponse
  stream_response : DeepSeekMockStream
  buffered_requests : Array[@provider_utils.HttpRequest]
  stream_requests : Array[@provider_utils.HttpRequest]
}

///|
fn DeepSeekMockTransport::new(
  buffered_response : @provider_utils.HttpResponse,
  stream_response : DeepSeekMockStream,
) -> DeepSeekMockTransport {
  {
    buffered_response,
    stream_response,
    buffered_requests: [],
    stream_requests: [],
  }
}

///|
impl @provider_utils.HttpTransport for DeepSeekMockTransport with fn fetch(
  self,
  request,
) -> @provider_utils.HttpResponse {
  self.buffered_requests.push(request)
  self.buffered_response
}

///|
impl @provider_utils.HttpTransport for DeepSeekMockTransport with fn fetch_stream(
  self,
  request,
) -> &@provider_utils.HttpStreamResponse {
  self.stream_requests.push(request)
  self.stream_response as &@provider_utils.HttpStreamResponse
}

///|
fn deepseek_sse_line(json : Json) -> String {
  "data: " + json.stringify()
}

///|
fn deepseek_json_response() -> String {
  (
    {
      "id": "ds-response-1",
      "model": "deepseek-chat",
      "created": 1700000100,
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "reasoning_content": "plan",
            "content": "answer",
            "tool_calls": [
              {
                "type": "function",
                "function": {
                  "name": "lookup",
                  "arguments": "{\"q\":\"moon\"}",
                },
              },
            ],
          },
          "finish_reason": "tool_calls",
        },
      ],
      "usage": {
        "prompt_tokens": 3,
        "completion_tokens": 5,
        "total_tokens": 8,
        "prompt_cache_hit_tokens": 1,
        "prompt_cache_miss_tokens": 2,
      },
    } : Json).stringify()
}

///|
fn deepseek_stream_chunks() -> Array[String] {
  [
    deepseek_sse_line({
      "id": "ds-stream-1",
      "model": "deepseek-chat",
      "created": 1700000101,
      "choices": [
        { "delta": { "reasoning_content": "plan" }, "finish_reason": null },
      ],
    }),
    "",
    deepseek_sse_line({
      "choices": [
        {
          "delta": { "reasoning_content": " carefully" },
          "finish_reason": null,
        },
      ],
    }),
    "",
    deepseek_sse_line({
      "choices": [{ "delta": { "content": "answer" }, "finish_reason": null }],
    }),
    "",
    deepseek_sse_line({
      "choices": [
        {
          "delta": {
            "tool_calls": [
              {
                "index": 0,
                "id": "call-1",
                "function": { "name": "lookup", "arguments": "{\"q\":" },
              },
            ],
          },
          "finish_reason": null,
        },
      ],
    }),
    "",
    deepseek_sse_line({
      "choices": [
        {
          "delta": {
            "tool_calls": [
              { "index": 0, "function": { "arguments": "\"moon\"}" } },
            ],
          },
          "finish_reason": "tool_calls",
        },
      ],
    }),
    "",
    deepseek_sse_line({
      "choices": [],
      "usage": {
        "prompt_tokens": 4,
        "completion_tokens": 6,
        "total_tokens": 10,
        "prompt_cache_hit_tokens": 2,
        "prompt_cache_miss_tokens": 1,
      },
    }),
    "",
    deepseek_sse_line("[DONE]"),
    "",
  ]
}

///|
async test "DeepSeek drives a JSON request and preserves diagnostics" {
  let transport = DeepSeekMockTransport::new(
    @provider_utils.HttpResponse::text(
      status_code=200,
      body=deepseek_json_response(),
      headers={ "x-request-id": "ds-request-1" },
    ),
    DeepSeekMockStream::new([]),
  )
  let model = DeepSeekLanguageModelV4::new(
      deepseek_chat(
        "deepseek-chat",
        api_key="test-key",
        base_url="https://deepseek.test",
        http_transport=transport,
        id_generator=() => "deepseek-generated-call",
      ),
    )
    as &@provider.LanguageModelV4
  let tool = @provider.ToolDefinition::new("lookup", {
    "type": "object",
    "properties": { "q": { "type": "string" } },
  })
  let response = @ai.generate_text(
    model,
    prompt="find moon",
    tools=[tool],
    retry_policy=@provider.RetryPolicy::none(),
  )
  let legacy = response.to_chat_response()
  assert_eq(legacy.text, "answer")
  assert_eq(legacy.reasoning, "plan")
  assert_eq(legacy.finish_reason, @provider.ToolCalls)
  assert_eq(legacy.tool_calls.length(), 1)
  assert_eq(legacy.tool_calls[0].id, "deepseek-generated-call")
  assert_eq(legacy.tool_calls[0].arguments, "{\"q\":\"moon\"}")
  assert_eq(legacy.usage.total_tokens, 8)
  assert_eq(legacy.usage.cached_input_tokens, 1)
  assert_eq(legacy.usage.cache_write_input_tokens, 0)
  assert_eq(response.finish_reason.raw, Some("tool_calls"))
  json_inspect(response.usage.raw.unwrap(), content={
    "prompt_tokens": 3,
    "completion_tokens": 5,
    "total_tokens": 8,
    "prompt_cache_hit_tokens": 1,
    "prompt_cache_miss_tokens": 2,
  })
  assert_eq(response.response.unwrap().status_code, Some(200))
  assert_eq(response.response.unwrap().id, Some("ds-response-1"))
  assert_eq(transport.buffered_requests.length(), 1)
  let request = transport.buffered_requests[0]
  assert_eq(request.url, "https://deepseek.test/chat/completions")
  assert_eq(request.headers["Authorization"], "Bearer test-key")
  assert_true(request.body_text().contains("\"tools\""))
}

///|
async test "DeepSeek API errors retain structured HTTP diagnostics" {
  let transport = DeepSeekMockTransport::new(
    @provider_utils.HttpResponse::text(
      status_code=401,
      body="{\"error\":{\"message\":\"invalid key\"}}",
      headers={ "x-request-id": "ds-error-1" },
    ),
    DeepSeekMockStream::new([]),
  )
  let model = DeepSeekLanguageModelV4::new(
      deepseek_chat(
        "deepseek-chat",
        api_key="bad-key",
        base_url="https://deepseek.test",
        http_transport=transport,
      ),
    )
    as &@provider.LanguageModelV4
  try
    @ai.generate_text(
      model,
      prompt="hello",
      retry_policy=@provider.RetryPolicy::none(),
    )
    |> ignore
  catch {
    @provider.APICallError(
      message~,
      url~,
      request_body~,
      request_headers~,
      status_code~,
      response_headers~,
      response_body~,
      is_retryable~
    ) => {
      assert_eq(message, "invalid key")
      assert_eq(url, "https://deepseek.test/chat/completions")
      assert_true(request_body.contains("\"model\":\"deepseek-chat\""))
      assert_eq(request_headers["Authorization"], "Bearer bad-key")
      assert_eq(status_code, 401)
      assert_eq(response_headers["x-request-id"], "ds-error-1")
      assert_true(response_body.contains("invalid key"))
      assert_eq(is_retryable, false)
    }
    _ => fail("unexpected DeepSeek error")
  } noraise {
    _ => fail("expected DeepSeek API call error")
  }
}

///|
async test "DeepSeek SSE keeps reasoning, text, and tool transitions ordered" {
  let transport = DeepSeekMockTransport::new(
    @provider_utils.HttpResponse::text(status_code=200, body="{}"),
    DeepSeekMockStream::new(deepseek_stream_chunks(), headers={
      "x-request-id": "ds-stream-request",
    }),
  )
  let model = DeepSeekLanguageModelV4::new(
      deepseek_chat(
        "deepseek-chat",
        api_key="test-key",
        base_url="https://deepseek.test",
        http_transport=transport,
      ),
    )
    as &@provider.LanguageModelV4
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  let text_deltas : Array[String] = []
  let reasoning_deltas : Array[String] = []
  let tool_calls : Array[@provider.ToolCall] = []
  let response_metadata : Array[@provider.ResponseMetadata] = []
  let response = @ai.stream_text(
    model,
    prompt="find moon",
    on_event=event => {
      events.push(event)
      match event {
        @provider.V4TextDelta(delta~, ..) => text_deltas.push(delta)
        @provider.V4ReasoningDelta(delta~, ..) => reasoning_deltas.push(delta)
        @provider.V4ToolCallReady(call) => tool_calls.push(call)
        @provider.V4ResponseMetadataReady(metadata) =>
          response_metadata.push(metadata)
        _ => ()
      }
    },
    retry_policy=@provider.RetryPolicy::none(),
  )
  assert_eq(text_deltas.join(""), "answer")
  assert_eq(reasoning_deltas.join(""), "plan carefully")
  assert_eq(tool_calls.length(), 1)
  assert_eq(tool_calls[0].arguments, "{\"q\":\"moon\"}")
  assert_eq(response_metadata.length(), 1)
  assert_eq(response_metadata[0].id, Some("ds-stream-1"))
  assert_eq(response_metadata[0].model_id, Some("deepseek-chat"))
  assert_eq(response_metadata[0].created_at, Some(1700000101))
  assert_eq(response.usage.input_tokens.total, Some(4))
  assert_eq(response.usage.output_tokens.total, Some(6))
  assert_eq(response.finish_reason.unified, @provider.V4FinishToolCalls)
  assert_eq(response.finish_reason.raw, Some("tool_calls"))
  assert_true(
    response.usage.raw
    is Some({ "prompt_tokens": 4, "completion_tokens": 6, .. }),
  )
  assert_true(
    events.any(event => {
      event is @provider.V4ReasoningStart(id="reasoning-0", ..)
    }),
  )
  assert_true(
    events.any(event => event is @provider.V4ReasoningEnd(id="reasoning-0", ..)),
  )
  assert_true(
    events.any(event => event is @provider.V4TextStart(id="text-0", ..)),
  )
  assert_true(
    events.any(event => event is @provider.V4TextEnd(id="text-0", ..)),
  )
  assert_true(events.any(event => event is @provider.V4ToolCallReady(_)))
  assert_true(
    events.any(event => {
      event
      is @provider.V4Finish(
        reason={ unified: @provider.V4FinishToolCalls, .. },
        ..
      )
    }),
  )
  assert_eq(transport.stream_requests.length(), 1)
  assert_eq(
    transport.stream_requests[0].headers["Authorization"],
    "Bearer test-key",
  )
}
