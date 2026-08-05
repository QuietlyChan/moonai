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
