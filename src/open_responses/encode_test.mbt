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
    frequency_penalty=-0.1,
    presence_penalty=0.3,
    seed=42,
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

///|
test "encode Open Responses non-streaming request" {
  let options = @moonai.ChatCallOptions::new([@moonai.Message::user("hello")])
  json_inspect(encode_responses_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": [{ "type": "input_text", "text": "hello" }],
      },
    ],
  })
}

///|
test "encode Open Responses multimodal content parts" {
  let options = @moonai.ChatCallOptions::new([
    @moonai.Message::user_parts([
      @moonai.ContentPart::text("Describe these inputs"),
      @moonai.ContentPart::image_url("https://example.com/moon.png"),
      @moonai.ContentPart::image_data(data="aW1hZ2U=", media_type="image/png"),
      @moonai.ContentPart::file_data(
        data="ZmlsZQ==",
        media_type="application/pdf",
        filename="guide.pdf",
      ),
    ]),
  ])
  json_inspect(encode_responses_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": [
          { "type": "input_text", "text": "Describe these inputs" },
          { "type": "input_image", "image_url": "https://example.com/moon.png" },
          {
            "type": "input_image",
            "image_url": "data:image/png;base64,aW1hZ2U=",
          },
          {
            "type": "input_file",
            "filename": "guide.pdf",
            "file_data": "data:application/pdf;base64,ZmlsZQ==",
          },
        ],
      },
    ],
  })
}

///|
test "Open Responses rejects unsupported audio content explicitly" {
  let options = @moonai.ChatCallOptions::new([
    @moonai.Message::user_parts([
      @moonai.ContentPart::audio_data(data="YXVkaW8=", format="wav"),
    ]),
  ])
  try encode_responses_request("gpt-test", options) catch {
    Failure::Failure(message) =>
      assert_true(
        message.contains("Open Responses does not accept audio content"),
      )
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected audio content to be rejected")
  }
}

///|
test "encode Open Responses JSON Schema response format" {
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
  json_inspect(encode_responses_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": [{ "type": "input_text", "text": "answer" }],
      },
    ],
    "text": {
      "format": {
        "type": "json_schema",
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
