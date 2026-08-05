///|
test "Alibaba chat maps provider-specific options and capabilities" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    top_k=20.0,
    frequency_penalty=0.4,
    provider_options=AlibabaLanguageModelChatOptions::new(
      enable_thinking=true,
      thinking_budget=1024,
      parallel_tool_calls=false,
    ).to_provider_options(),
  )
  json_inspect(encode_alibaba_chat_request("qwen3-max", options), content={
    "model": "qwen3-max",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
    ],
    "top_k": 20,
    "enable_thinking": true,
    "thinking_budget": 1024,
    "parallel_tool_calls": false,
  })
}

///|
test "Alibaba maps normalized reasoning to thinking controls" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("think")],
    reasoning_effort=@provider.High,
    max_output_tokens=16_384,
  )
  json_inspect(encode_alibaba_chat_request("qwen3-max", options), content={
    "model": "qwen3-max",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "think" }] },
    ],
    "max_tokens": 16384,
    "enable_thinking": true,
    "thinking_budget": 9830,
  })
}

///|
test "Alibaba provider reasoning options take precedence over normalized reasoning" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("think")],
    reasoning_effort=@provider.Disabled,
    provider_options=AlibabaLanguageModelChatOptions::new(
      enable_thinking=true,
      thinking_budget=2048,
    ).to_provider_options(),
  )
  json_inspect(encode_alibaba_chat_request("qwen3-max", options), content={
    "model": "qwen3-max",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "think" }] },
    ],
    "enable_thinking": true,
    "thinking_budget": 2048,
  })
}

///|
test "Alibaba chat forwards content-part cache control" {
  let cache_control = AlibabaCacheControl::new(cache_type="ephemeral")
  let cached = @provider.LanguageModelContentPart::text("cached").with_provider_options(
    cache_control.to_provider_options(),
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([cached]),
  ])
  json_inspect(
    encode_alibaba_chat_request("qwen3-max", options, stream=false),
    content={
      "model": "qwen3-max",
      "messages": [
        {
          "role": "user",
          "content": [
            {
              "type": "text",
              "text": "cached",
              "cache_control": { "type": "ephemeral" },
            },
          ],
        },
      ],
    },
  )
}

///|
test "Alibaba applies message cache control to the last user part" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts(
      [
        @provider.LanguageModelContentPart::text("Describe"),
        @provider.LanguageModelContentPart::image_url(
          "https://example.com/image.png",
        ),
      ],
      provider_options={
        "alibaba": { "cacheControl": { "type": "ephemeral" } },
      },
    ),
  ])
  json_inspect(
    encode_alibaba_chat_request("qwen3-max", options, stream=false),
    content={
      "model": "qwen3-max",
      "messages": [
        {
          "role": "user",
          "content": [
            { "type": "text", "text": "Describe" },
            {
              "type": "image_url",
              "image_url": { "url": "https://example.com/image.png" },
              "cache_control": { "type": "ephemeral" },
            },
          ],
        },
      ],
    },
  )
}

///|
test "Alibaba maps assistant and tool cache control" {
  let cache : Map[String, Json] = {
    "alibaba": { "cacheControl": { "type": "ephemeral" } },
  }
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant(
      "answer",
      reasoning_content="reasoning",
      provider_options=cache,
    ),
    @provider.LanguageModelMessage::tool(
      "call-1",
      "result",
      provider_options=cache,
    ),
  ])
  json_inspect(
    encode_alibaba_chat_request("qwen3-max", options, stream=false),
    content={
      "model": "qwen3-max",
      "messages": [
        {
          "role": "assistant",
          "content": [
            {
              "type": "text",
              "text": "answerreasoning",
              "cache_control": { "type": "ephemeral" },
            },
          ],
        },
        {
          "role": "tool",
          "tool_call_id": "call-1",
          "content": [
            {
              "type": "text",
              "text": "result",
              "cache_control": { "type": "ephemeral" },
            },
          ],
        },
      ],
    },
  )
}

///|
test "Alibaba serializes structured tool results" {
  let result = @provider.LanguageModelToolResult::json(
    tool_call_id="call-1",
    tool_name="lookup",
    value={ "ok": true },
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::tool_content([
      @provider.LanguageModelContentPart::tool_result(result),
    ]),
  ])
  json_inspect(
    encode_alibaba_chat_request("qwen3-max", options, stream=false),
    content={
      "model": "qwen3-max",
      "messages": [
        { "role": "tool", "tool_call_id": "call-1", "content": "{\"ok\":true}" },
      ],
    },
  )
}

///|
test "Alibaba encodes assistant tool-call content parts" {
  let call = @provider.ToolCall::new(
    id="call-part",
    name="lookup",
    arguments="{}",
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant_parts([
      @provider.LanguageModelContentPart::tool_call(call),
    ]),
  ])
  json_inspect(
    encode_alibaba_chat_request("qwen3-max", options, stream=false),
    content={
      "model": "qwen3-max",
      "messages": [
        {
          "role": "assistant",
          "content": null,
          "tool_calls": [
            {
              "id": "call-part",
              "type": "function",
              "function": { "name": "lookup", "arguments": "{}" },
            },
          ],
        },
      ],
    },
  )
}

///|
test "Alibaba warns after four prompt cache breakpoints" {
  let parts : Array[@provider.LanguageModelContentPart] = []
  for index = 0; index < 5; index = index + 1 {
    parts.push(
      @provider.LanguageModelContentPart::text("part-\{index}").with_provider_options({
          "alibaba": { "cacheControl": { "type": "ephemeral" } },
        },
      ),
    )
  }
  let conversion = alibaba_prompt_converter(
    [@provider.LanguageModelMessage::user_parts(parts)],
    false,
    "alibaba.chat",
  )
  assert_eq(conversion.warnings.length(), 1)
  assert_true(conversion.warnings[0] is @provider.Other(..))
  match conversion.warnings[0] {
    @provider.Other(message~) =>
      assert_true(message.contains("Max breakpoint limit exceeded"))
    _ => fail("expected cache breakpoint warning")
  }
}

///|
async test "Alibaba HTTP chat uses its provider-specific prompt converter" {
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever(
        (request, body, connection) => {
          assert_eq(request.path, "/v1/chat/completions")
          let request_body = body.read_all().text()
          assert_true(
            request_body.contains(
              "\"content\":[{\"type\":\"text\",\"text\":\"first\"},{\"type\":\"text\",\"text\":\"second\",\"cache_control\":{\"type\":\"ephemeral\"}}]",
            ),
          )
          assert_true(request_body.contains("\"enable_thinking\":true"))
          connection.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          connection.write(
            "{\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"ok\",\"tool_calls\":[{\"type\":\"function\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{}\"}}]},\"finish_reason\":\"tool_calls\"}],\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":1,\"total_tokens\":3}}",
          )
        },
        max_connections=1,
      )
    }
    let model = alibaba_chat(
      "qwen3-max",
      api_key="test-key",
      base_url="http://127.0.0.1:\{server.addr.port()}/v1",
      idle_timeout_ms=2_000,
      id_generator=() => "alibaba-generated-call",
    )
    let cache : Map[String, Json] = {
      "alibaba": { "cacheControl": { "type": "ephemeral" } },
    }
    let response = @ai.generate_text(
      AlibabaLanguageModelV4::new(model) as &@provider.LanguageModelV4,
      messages=[
        @ai.ModelMessage::user_parts(
          [
            @ai.ModelContentPart::text("first"),
            @ai.ModelContentPart::text("second"),
          ],
          provider_options=cache,
        ),
      ],
      reasoning_effort=@provider.High,
    )
    assert_eq(response.text(), "ok")
    match response.content[1] {
      @provider.GeneratedToolCallOutput(call) =>
        assert_eq(call.id, "alibaba-generated-call")
      _ => fail("expected generated Alibaba tool call")
    }
    assert_eq(response.usage.input_tokens.total, Some(2))
    assert_eq(response.usage.output_tokens.total, Some(1))
    assert_eq(response.finish_reason.raw, Some("tool_calls"))
    assert_true(response.usage.raw is Some({ "total_tokens": 3, .. }))
  }
}
