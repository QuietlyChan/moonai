///|
test "encode OpenAI-compatible streaming request" {
  let options = @moonai.ChatCallOptions::new(
    [@moonai.Message::user("weather")],
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
    response_format=@moonai.JsonObject,
    temperature=0.2,
  )
  json_inspect(encode_chat_request("gpt-test", options), content={
    "model": "gpt-test",
    "messages": [{ "role": "user", "content": "weather" }],
    "stream": true,
    "stream_options": { "include_usage": true },
    "temperature": 0.2,
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get weather",
          "parameters": {
            "type": "object",
            "properties": { "city": { "type": "string" } },
            "required": ["city"],
          },
          "strict": true,
        },
      },
    ],
    "tool_choice": "auto",
    "response_format": { "type": "json_object" },
  })
}
