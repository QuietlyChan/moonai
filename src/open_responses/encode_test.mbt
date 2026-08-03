///|
test "encode Open Responses streaming request" {
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
        { "type": "object" },
        strict=true,
      ),
    ],
    tool_choice=@moonai.Required,
    max_output_tokens=1024,
    response_format=@moonai.JsonObject,
  )
  json_inspect(encode_responses_request("gpt-test", options), content={
    "model": "gpt-test",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": [{ "type": "input_text", "text": "weather" }],
      },
      {
        "type": "function_call",
        "call_id": "call_weather",
        "name": "get_weather",
        "arguments": "{\"city\":\"Hangzhou\"}",
      },
      {
        "type": "function_call_output",
        "call_id": "call_weather",
        "output": "sunny",
      },
    ],
    "stream": true,
    "instructions": "Be concise",
    "max_output_tokens": 1024,
    "tools": [
      {
        "type": "function",
        "name": "get_weather",
        "description": "Get weather",
        "parameters": { "type": "object" },
        "strict": true,
      },
    ],
    "tool_choice": "required",
    "text": { "format": { "type": "json_object" } },
  })
}
