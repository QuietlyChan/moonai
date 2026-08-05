///|
test "decode the public DeepSeek error data shape" {
  let decoded = decode_deepseek_error_data({
    "error": {
      "message": "invalid request",
      "type": "invalid_request_error",
      "param": Json::null(),
      "code": "bad_request",
    },
  }).unwrap()
  assert_eq(decoded.error.message, "invalid request")
  assert_eq(decoded.error.error_type, Some("invalid_request_error"))
  assert_eq(decoded.error.param, Some(Json::null()))
  assert_eq(decoded.error.code, Some("bad_request"))
}

///|
test "DeepSeek distinguishes omitted and explicit tool choice" {
  let tool = @provider.ToolDefinition::new(
    "lookup",
    { "type": "object" },
    description="Look up a record",
  )
  let omitted = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("find it")],
    tools=[tool],
  )
  json_inspect(encode_deepseek_chat_request("deepseek-chat", omitted), content={
    "model": "deepseek-chat",
    "messages": [{ "role": "user", "content": "find it" }],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "lookup",
          "description": "Look up a record",
          "parameters": { "type": "object" },
        },
      },
    ],
  })
  let explicit = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("find it")],
    tools=[tool],
    tool_choice=@provider.Auto,
  )
  json_inspect(encode_deepseek_chat_request("deepseek-chat", explicit), content={
    "model": "deepseek-chat",
    "messages": [{ "role": "user", "content": "find it" }],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "lookup",
          "description": "Look up a record",
          "parameters": { "type": "object" },
        },
      },
    ],
    "tool_choice": "auto",
  })
}

///|
test "DeepSeek encodes typed thinking and structured-output options" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("return a count")],
    response_format=@provider.ResponseFormat::json(
      schema={
        "type": "object",
        "properties": { "count": { "type": "integer" } },
        "required": ["count"],
      },
      name="count_response",
    ),
    provider_options=DeepSeekLanguageModelChatOptions::new(
      thinking_type="adaptive",
      reasoning_effort="max",
      strict_json_schema=false,
    ).to_provider_options(),
  )
  json_inspect(
    encode_deepseek_chat_request(
      "deepseek-v4",
      options,
      supports_structured_outputs=true,
    ),
    content={
      "model": "deepseek-v4",
      "messages": [{ "role": "user", "content": "return a count" }],
      "response_format": {
        "type": "json_schema",
        "json_schema": {
          "name": "count_response",
          "schema": {
            "type": "object",
            "properties": { "count": { "type": "integer" } },
            "required": ["count"],
          },
          "strict": false,
        },
      },
      "thinking": { "type": "adaptive" },
      "reasoning_effort": "max",
    },
  )
}

///|
test "DeepSeek encodes assistant tool-call content parts" {
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
  json_inspect(encode_deepseek_chat_request("deepseek-chat", options), content={
    "model": "deepseek-chat",
    "messages": [
      {
        "role": "assistant",
        "content": "",
        "tool_calls": [
          {
            "id": "call-part",
            "type": "function",
            "function": { "name": "lookup", "arguments": "{}" },
          },
        ],
      },
    ],
  })
}

///|
test "DeepSeek encodes structured and text tool results" {
  let call = @provider.ToolCall::new(
    id="call-result",
    name="lookup",
    arguments="{\"city\":\"Shanghai\"}",
  )
  let json_result = @provider.LanguageModelToolResult::json(
    tool_call_id="call-result",
    tool_name="lookup",
    value={ "temperature": 18 },
  )
  let text_result = @provider.LanguageModelToolResult::text(
    tool_call_id="call-result",
    tool_name="lookup",
    value="sunny",
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant_parts([
      @provider.LanguageModelContentPart::tool_call(call),
    ]),
    @provider.LanguageModelMessage::tool_parts("call-result", [
      @provider.LanguageModelContentPart::tool_result(json_result),
      @provider.LanguageModelContentPart::tool_result(text_result),
    ]),
  ])
  let body = encode_deepseek_chat_request("deepseek-chat", options)
  match body {
    {
      "messages": [
        _,
        { "role": "tool", "content": String(json_value), .. },
        { "role": "tool", "content": String(text_value), .. },
        ..,
      ],
      ..
    } => {
      assert_eq(json_value, "{\"temperature\":18}")
      assert_eq(text_value, "sunny")
    }
    _ => fail("expected a serialized DeepSeek tool result")
  }
}

///|
test "DeepSeek preserves reasoning content parts on assistant turns" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user("think then answer"),
    @provider.LanguageModelMessage::assistant_parts([
      @provider.LanguageModelContentPart::reasoning("first inspect the data"),
      @provider.LanguageModelContentPart::text("the answer is 42"),
    ]),
  ])
  json_inspect(encode_deepseek_chat_request("deepseek-chat", options), content={
    "model": "deepseek-chat",
    "messages": [
      { "role": "user", "content": "think then answer" },
      {
        "role": "assistant",
        "content": "the answer is 42",
        "reasoning_content": "first inspect the data",
      },
    ],
  })
  json_inspect(
    encode_deepseek_chat_request(
      "deepseek-v4-pro",
      @provider.ChatCallOptions::new([
        @provider.LanguageModelMessage::assistant_parts([
          @provider.LanguageModelContentPart::text("prior answer"),
        ]),
      ]),
    ),
    content={
      "model": "deepseek-v4-pro",
      "messages": [
        {
          "role": "assistant",
          "content": "prior answer",
          "reasoning_content": "",
        },
      ],
    },
  )
}
