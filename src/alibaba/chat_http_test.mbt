///|
priv struct AlibabaChatMockStream {
  status : Int
  response_headers : Map[String, String]
  chunks : Array[String]
  next_chunk : Ref[Int]
}

///|
fn AlibabaChatMockStream::new(
  chunks : Array[String],
  status? : Int = 200,
  headers? : Map[String, String] = Map([]),
) -> AlibabaChatMockStream {
  {
    status,
    response_headers: @provider_utils.copy_headers(headers),
    chunks,
    next_chunk: Ref(0),
  }
}

///|
impl @provider_utils.HttpStreamResponse for AlibabaChatMockStream with fn status_code(
  self,
) -> Int {
  self.status
}

///|
impl @provider_utils.HttpStreamResponse for AlibabaChatMockStream with fn reason(
  _self,
) -> String {
  "OK"
}

///|
impl @provider_utils.HttpStreamResponse for AlibabaChatMockStream with fn headers(
  self,
) -> Map[String, String] {
  @provider_utils.copy_headers(self.response_headers)
}

///|
impl @provider_utils.HttpStreamResponse for AlibabaChatMockStream with fn read_until(
  self,
  _separator,
) -> String? {
  guard self.next_chunk.val < self.chunks.length() else { return None }
  let chunk = self.chunks[self.next_chunk.val]
  self.next_chunk.val = self.next_chunk.val + 1
  Some(chunk)
}

///|
impl @provider_utils.HttpStreamResponse for AlibabaChatMockStream with fn read_all(
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
impl @provider_utils.HttpStreamResponse for AlibabaChatMockStream with fn close(
  _self,
) -> Unit {
  ()
}

///|
priv struct AlibabaChatMockTransport {
  buffered_response : @provider_utils.HttpResponse
  stream_response : AlibabaChatMockStream
  buffered_requests : Array[@provider_utils.HttpRequest]
  stream_requests : Array[@provider_utils.HttpRequest]
}

///|
fn AlibabaChatMockTransport::new(
  buffered_response : @provider_utils.HttpResponse,
  stream_response : AlibabaChatMockStream,
) -> AlibabaChatMockTransport {
  {
    buffered_response,
    stream_response,
    buffered_requests: [],
    stream_requests: [],
  }
}

///|
impl @provider_utils.HttpTransport for AlibabaChatMockTransport with fn fetch(
  self,
  request,
) -> @provider_utils.HttpResponse {
  self.buffered_requests.push(request)
  self.buffered_response
}

///|
impl @provider_utils.HttpTransport for AlibabaChatMockTransport with fn fetch_stream(
  self,
  request,
) -> &@provider_utils.HttpStreamResponse {
  self.stream_requests.push(request)
  self.stream_response as &@provider_utils.HttpStreamResponse
}

///|
fn alibaba_chat_sse_line(value : Json) -> String {
  "data: " + value.stringify()
}

///|
fn alibaba_chat_json_response() -> String {
  (
    {
      "id": "ali-response-1",
      "model": "qwen-plus",
      "created": 1700000200,
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "reasoning_content": "plan",
            "content": "answer",
            "tool_calls": [
              {
                "id": "call-1",
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
        "prompt_tokens": 10,
        "completion_tokens": 6,
        "total_tokens": 16,
        "prompt_tokens_details": {
          "cached_tokens": 3,
          "cache_creation_input_tokens": 2,
        },
        "completion_tokens_details": { "reasoning_tokens": 4 },
      },
    } : Json).stringify()
}

///|
fn alibaba_chat_stream_chunks() -> Array[String] {
  [
    alibaba_chat_sse_line({
      "id": "ali-stream-1",
      "model": "qwen-plus",
      "created": 1700000201,
      "choices": [
        {
          "index": 0,
          "delta": { "reasoning_content": "plan" },
          "finish_reason": null,
        },
      ],
    }),
    "",
    alibaba_chat_sse_line({
      "choices": [
        {
          "index": 0,
          "delta": { "reasoning_content": " carefully" },
          "finish_reason": null,
        },
      ],
    }),
    "",
    alibaba_chat_sse_line({
      "choices": [
        { "index": 0, "delta": { "content": "answer" }, "finish_reason": null },
      ],
    }),
    "",
    alibaba_chat_sse_line({
      "choices": [
        {
          "index": 0,
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
    alibaba_chat_sse_line({
      "choices": [
        {
          "index": 0,
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
    alibaba_chat_sse_line({
      "choices": [],
      "usage": {
        "prompt_tokens": 9,
        "completion_tokens": 7,
        "total_tokens": 16,
        "prompt_tokens_details": {
          "cached_tokens": 2,
          "cache_creation_input_tokens": 1,
        },
        "completion_tokens_details": { "reasoning_tokens": 5 },
      },
    }),
    "",
    "data: [DONE]",
    "",
  ]
}

///|
async test "Alibaba drives a V4 JSON request with native options and usage" {
  let transport = AlibabaChatMockTransport::new(
    @provider_utils.HttpResponse::text(
      status_code=200,
      body=alibaba_chat_json_response(),
      headers={ "x-request-id": "ali-request-1" },
    ),
    AlibabaChatMockStream::new([]),
  )
  let model = alibaba(
    "qwen-plus",
    api_key="test-key",
    base_url="https://alibaba.test/compatible-mode/v1",
    http_transport=transport,
  )
  let tool = @provider_utils.Tool::function({
    "type": "object",
    "properties": { "q": { "type": "string" } },
  })
  let response = @ai.generate_text(
    model,
    prompt="find moon",
    tools=@provider_utils.tool_set([("lookup", tool)]),
    response_format=@provider.ResponseFormat::json(
      schema={ "type": "object" },
      name="answer",
    ),
    top_k=7.0,
    frequency_penalty=0.5,
    provider_options=AlibabaLanguageModelChatOptions::new(
      enable_thinking=true,
      thinking_budget=2048,
      parallel_tool_calls=false,
    ).to_provider_options(),
    retry_policy=@provider.RetryPolicy::none(),
  )
  let legacy = response.to_chat_response()
  assert_eq(legacy.text, "answer")
  assert_eq(legacy.reasoning, "plan")
  assert_eq(legacy.finish_reason, @provider.ToolCalls)
  assert_eq(legacy.tool_calls.length(), 1)
  assert_eq(legacy.tool_calls[0].id, "call-1")
  assert_eq(legacy.tool_calls[0].arguments, "{\"q\":\"moon\"}")
  assert_eq(response.usage.input_tokens.total, Some(10))
  assert_eq(response.usage.input_tokens.no_cache, Some(5))
  assert_eq(response.usage.input_tokens.cache_read, Some(3))
  assert_eq(response.usage.input_tokens.cache_write, Some(2))
  assert_eq(response.usage.output_tokens.total, Some(6))
  assert_eq(response.usage.output_tokens.reasoning, Some(4))
  assert_eq(response.finish_reason.raw, Some("tool_calls"))
  assert_true(
    response.warnings.any(warning => {
      warning is @provider.Warning::Unsupported(feature="frequencyPenalty", ..)
    }),
  )
  assert_eq(response.response.unwrap().id, Some("ali-response-1"))
  assert_eq(response.response.unwrap().status_code, Some(200))
  assert_eq(transport.buffered_requests.length(), 1)
  let request = transport.buffered_requests[0]
  assert_eq(
    request.url,
    "https://alibaba.test/compatible-mode/v1/chat/completions",
  )
  assert_eq(request.headers["Authorization"], "Bearer test-key")
  match @json.parse(request.body_text()) {
    {
      "model": String(model_id),
      "messages": messages,
      "top_k": Number(top_k, ..),
      "response_format": response_format,
      "enable_thinking": True,
      "thinking_budget": Number(thinking_budget, ..),
      "tools": tools,
      "tool_choice": String(tool_choice),
      "parallel_tool_calls": False,
      ..
    } => {
      assert_eq(model_id, "qwen-plus")
      assert_eq(top_k, 7.0)
      assert_eq(thinking_budget, 2048.0)
      assert_eq(tool_choice, "auto")
      json_inspect(messages, content=[
        { "role": "user", "content": [{ "type": "text", "text": "find moon" }] },
      ])
      json_inspect(response_format, content={
        "type": "json_schema",
        "json_schema": { "name": "answer", "schema": { "type": "object" } },
      })
      json_inspect(tools, content=[
        {
          "type": "function",
          "function": {
            "name": "lookup",
            "parameters": {
              "type": "object",
              "properties": { "q": { "type": "string" } },
            },
          },
        },
      ])
    }
    _ => fail("expected Alibaba-specific chat request fields")
  }
}

///|
async test "Alibaba SSE preserves reasoning text tools and cache usage" {
  let transport = AlibabaChatMockTransport::new(
    @provider_utils.HttpResponse::text(status_code=200, body="{}"),
    AlibabaChatMockStream::new(alibaba_chat_stream_chunks(), headers={
      "x-request-id": "ali-stream-request",
    }),
  )
  let model = alibaba(
    "qwen-plus",
    api_key="test-key",
    base_url="https://alibaba.test/compatible-mode/v1",
    http_transport=transport,
  )
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  let text_deltas : Array[String] = []
  let reasoning_deltas : Array[String] = []
  let tool_calls : Array[@provider.LanguageModelV4ToolCall] = []
  let result = @ai.stream_text(
    model,
    prompt="find moon",
    on_event=event => {
      events.push(event)
      match event {
        @provider.V4TextDelta(delta~, ..) => text_deltas.push(delta)
        @provider.V4ReasoningDelta(delta~, ..) => reasoning_deltas.push(delta)
        @provider.V4ToolCallReady(call) => tool_calls.push(call)
        _ => ()
      }
    },
    retry_policy=@provider.RetryPolicy::none(),
  )
  assert_eq(text_deltas.join(""), "answer")
  assert_eq(reasoning_deltas.join(""), "plan carefully")
  assert_eq(tool_calls.length(), 1)
  assert_eq(tool_calls[0].tool_call_id, "call-1")
  assert_eq(tool_calls[0].tool_name, "lookup")
  assert_eq(tool_calls[0].input, "{\"q\":\"moon\"}")
  assert_eq(result.usage.input_tokens.total, Some(9))
  assert_eq(result.usage.input_tokens.no_cache, Some(6))
  assert_eq(result.usage.input_tokens.cache_read, Some(2))
  assert_eq(result.usage.input_tokens.cache_write, Some(1))
  assert_eq(result.usage.output_tokens.total, Some(7))
  assert_eq(result.usage.output_tokens.reasoning, Some(5))
  assert_eq(result.finish_reason.unified, @provider.V4FinishToolCalls)
  assert_eq(result.finish_reason.raw, Some("tool_calls"))
  assert_eq(result.response.unwrap().id, Some("ali-stream-1"))
  assert_true(events.any(event => event is @provider.V4ReasoningStart(_)))
  assert_true(events.any(event => event is @provider.V4ReasoningEnd(_)))
  assert_true(events.any(event => event is @provider.V4TextStart(id="0", ..)))
  assert_true(events.any(event => event is @provider.V4TextEnd(id="0", ..)))
  assert_true(events.any(event => event is @provider.V4ToolCallReady(_)))
  let mut text_end_index = -1
  let mut tool_start_index = -1
  for index, event in events {
    match event {
      @provider.V4TextEnd(id="0", ..) if text_end_index < 0 =>
        text_end_index = index
      @provider.V4ToolInputStart(..) if tool_start_index < 0 =>
        tool_start_index = index
      _ => ()
    }
  }
  assert_true(text_end_index >= 0 && text_end_index < tool_start_index)
  assert_eq(transport.stream_requests.length(), 1)
  assert_eq(
    transport.stream_requests[0].headers["Authorization"],
    "Bearer test-key",
  )
  json_inspect(@json.parse(transport.stream_requests[0].body_text()), content={
    "model": "qwen-plus",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "find moon" }] },
    ],
    "stream": true,
    "stream_options": { "include_usage": true },
  })
}
