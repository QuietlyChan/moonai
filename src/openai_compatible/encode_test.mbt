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
    frequency_penalty=-0.1,
    presence_penalty=0.3,
    seed=42,
  )
  json_inspect(encode_chat_request("gpt-test", options), content={
    "model": "gpt-test",
    "messages": [{ "role": "user", "content": "weather" }],
    "stream": true,
    "stream_options": { "include_usage": true },
    "temperature": 0.2,
    "frequency_penalty": -0.1,
    "presence_penalty": 0.3,
    "seed": 42,
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

///|
test "encode OpenAI-compatible non-streaming request" {
  let options = @moonai.ChatCallOptions::new([@moonai.Message::user("hello")])
  json_inspect(encode_chat_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "messages": [{ "role": "user", "content": "hello" }],
  })
}

///|
test "encode OpenAI-compatible multimodal content parts" {
  let options = @moonai.ChatCallOptions::new([
    @moonai.Message::user_parts([
      @moonai.ContentPart::text("Describe these inputs"),
      @moonai.ContentPart::image_url("https://example.com/moon.png"),
      @moonai.ContentPart::image_data(data="aW1hZ2U=", media_type="image/png"),
      @moonai.ContentPart::audio_data(data="YXVkaW8=", format="wav"),
      @moonai.ContentPart::file_data(
        data="ZmlsZQ==",
        media_type="application/pdf",
        filename="guide.pdf",
      ),
    ]),
  ])
  json_inspect(encode_chat_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "messages": [
      {
        "role": "user",
        "content": [
          { "type": "text", "text": "Describe these inputs" },
          {
            "type": "image_url",
            "image_url": { "url": "https://example.com/moon.png" },
          },
          {
            "type": "image_url",
            "image_url": { "url": "data:image/png;base64,aW1hZ2U=" },
          },
          {
            "type": "input_audio",
            "input_audio": { "data": "YXVkaW8=", "format": "wav" },
          },
          {
            "type": "file",
            "file": {
              "filename": "guide.pdf",
              "file_data": "data:application/pdf;base64,ZmlsZQ==",
            },
          },
        ],
      },
    ],
  })
}

///|
test "encode OpenAI-compatible JSON Schema response format" {
  let schema : Json = {
    "type": "object",
    "properties": { "answer": { "type": "string" } },
    "required": ["answer"],
  }
  let options = @moonai.ChatCallOptions::new(
    [@moonai.Message::user("answer")],
    response_format=@moonai.JsonSchema(
      name="answer_schema",
      schema~,
      strict=true,
    ),
  )
  json_inspect(encode_chat_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "messages": [{ "role": "user", "content": "answer" }],
    "response_format": {
      "type": "json_schema",
      "json_schema": {
        "name": "answer_schema",
        "schema": {
          "type": "object",
          "properties": { "answer": { "type": "string" } },
          "required": ["answer"],
        },
        "strict": true,
      },
    },
  })
}
