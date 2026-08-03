///|
test "encode Anthropic Messages request" {
  let options = @moonai.ChatCallOptions::new(
    [
      @moonai.Message::system("Be concise"),
      @moonai.Message::user("weather"),
      @moonai.Message::assistant("", tool_calls=[
        @moonai.ToolCall::new(
          id="call_weather",
          name="get_weather",
          arguments="{\"city\":\"Hangzhou\"}",
        ),
      ]),
      @moonai.Message::tool("call_weather", "sunny"),
    ],
    tools=[
      @moonai.ToolDefinition::new(
        "get_weather",
        "Get weather",
        {
          "type": "object",
          "properties": { "city": { "type": "string" } },
          "required": ["city"],
        },
        strict=true,
      ),
    ],
    tool_choice=@moonai.Required,
    max_output_tokens=2048,
  )
  json_inspect(encode_messages_request("claude-test", options), content={
    "model": "claude-test",
    "messages": [
      { "role": "user", "content": [{ "type": "text", "text": "weather" }] },
      {
        "role": "assistant",
        "content": [
          {
            "type": "tool_use",
            "id": "call_weather",
            "name": "get_weather",
            "input": { "city": "Hangzhou" },
          },
        ],
      },
      {
        "role": "user",
        "content": [
          {
            "type": "tool_result",
            "tool_use_id": "call_weather",
            "content": [{ "type": "text", "text": "sunny" }],
          },
        ],
      },
    ],
    "max_tokens": 2048,
    "stream": true,
    "system": [{ "type": "text", "text": "Be concise" }],
    "tools": [
      {
        "name": "get_weather",
        "description": "Get weather",
        "input_schema": {
          "type": "object",
          "properties": { "city": { "type": "string" } },
          "required": ["city"],
        },
        "strict": true,
      },
    ],
    "tool_choice": { "type": "any" },
  })
}
