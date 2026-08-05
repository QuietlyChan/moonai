///|
test "encode Open Responses streaming request" {
  let options = @provider.ChatCallOptions::new(
    [
      @provider.LanguageModelMessage::system("Be concise"),
      @provider.LanguageModelMessage::user("weather"),
      @provider.LanguageModelMessage::assistant("", tool_calls=[
        @provider.ToolCall::new(
          id="call_weather",
          name="get_weather",
          arguments="{\"city\":\"Hangzhou\"}",
        ),
      ]),
      @provider.LanguageModelMessage::tool("call_weather", "sunny"),
    ],
    tools=[
      @provider.ToolDefinition::new(
        "get_weather",
        { "type": "object" },
        description="Get weather",
        strict=true,
      ),
    ],
    tool_choice=@provider.Required,
    max_output_tokens=1024,
    response_format=@provider.ResponseFormat::json(),
    reasoning_effort=@provider.Minimal,
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
    "frequency_penalty": -0.1,
    "presence_penalty": 0.3,
    "reasoning": { "effort": "low" },
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
    "text": { "format": { "type": "json_schema" } },
  })
}

///|
test "Open Responses encodes structured tool results and approvals" {
  let result = @provider.LanguageModelToolResult::json(
    tool_call_id="call-1",
    tool_name="weather",
    value={ "temperature": 18 },
  )
  let approval = @provider.LanguageModelToolApprovalResponse::new(
    approval_id="approval-1",
    approved=true,
    provider_executed=true,
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant("", tool_calls=[
      @provider.ToolCall::new(id="call-1", name="weather", arguments="{}"),
    ]),
    @provider.LanguageModelMessage::tool_content([
      @provider.LanguageModelContentPart::tool_result(result),
      @provider.LanguageModelContentPart::tool_approval_response(approval),
    ]),
  ])
  json_inspect(encode_responses_request("gpt-test", options), content={
    "model": "gpt-test",
    "input": [
      {
        "type": "function_call",
        "call_id": "call-1",
        "name": "weather",
        "arguments": "{}",
      },
      {
        "type": "function_call_output",
        "call_id": "call-1",
        "output": "{\"temperature\":18}",
      },
      {
        "type": "mcp_approval_response",
        "approval_request_id": "approval-1",
        "approve": true,
      },
    ],
    "stream": true,
  })
}

///|
test "Open Responses encodes assistant tool-call content parts" {
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
  json_inspect(encode_responses_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "input": [
      {
        "type": "function_call",
        "call_id": "call-part",
        "name": "lookup",
        "arguments": "{}",
      },
    ],
  })
}

///|
test "Open Responses resolves namespaced options and protects request fields" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    provider_options={
      "localTest": {
        "reasoningSummary": "concise",
        "store": false,
        "stream": false,
        "input": "overridden",
      },
    },
  )
  json_inspect(
    encode_responses_request(
      "gpt-test",
      options,
      provider_name="local-test.responses",
    ),
    content={
      "model": "gpt-test",
      "input": [
        {
          "type": "message",
          "role": "user",
          "content": [{ "type": "input_text", "text": "hello" }],
        },
      ],
      "stream": true,
      "reasoning": { "summary": "concise" },
    },
  )
}

///|
test "Open Responses typed options use the configured provider namespace" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("summarize")],
    provider_options=OpenResponsesLanguageModelOptions::new(
      reasoning_summary=ReasoningSummaryDetailed,
    ).to_provider_options(provider_name="localTest"),
  )
  json_inspect(
    encode_responses_request(
      "gpt-test",
      options,
      stream=false,
      provider_name="local-test.responses",
    ),
    content={
      "model": "gpt-test",
      "input": [
        {
          "type": "message",
          "role": "user",
          "content": [{ "type": "input_text", "text": "summarize" }],
        },
      ],
      "reasoning": { "summary": "detailed" },
    },
  )
}

///|
test "encode Open Responses non-streaming request" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user("hello"),
  ])
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
test "Open Responses omits an unspecified tool choice" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("weather")],
    tools=[
      @provider.ToolDefinition::new(
        "get_weather",
        { "type": "object" },
        description="Get weather",
      ),
    ],
  )
  json_inspect(encode_responses_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": [{ "type": "input_text", "text": "weather" }],
      },
    ],
    "tools": [
      {
        "type": "function",
        "name": "get_weather",
        "description": "Get weather",
        "parameters": { "type": "object" },
      },
    ],
  })
}

///|
test "Open Responses preserves an explicit tool choice without tools" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    tool_choice=@provider.NoTool,
  )
  json_inspect(encode_responses_request("model", options, stream=false), content={
    "model": "model",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": [{ "type": "input_text", "text": "hello" }],
      },
    ],
    "tool_choice": "none",
  })
}

///|
test "Open Responses preserves explicit false tool strictness" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("weather")],
    tools=[
      @provider.ToolDefinition::new(
        "get_weather",
        { "type": "object" },
        strict=false,
      ),
    ],
  )
  json_inspect(encode_responses_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "input": [
      {
        "type": "message",
        "role": "user",
        "content": [{ "type": "input_text", "text": "weather" }],
      },
    ],
    "tools": [
      {
        "type": "function",
        "name": "get_weather",
        "parameters": { "type": "object" },
        "strict": false,
      },
    ],
  })
}

///|
test "encode Open Responses multimodal content parts" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::text("Describe these inputs"),
      @provider.LanguageModelContentPart::image_url(
        "https://example.com/moon.png",
      ),
      @provider.LanguageModelContentPart::image_data(
        data="aW1hZ2U=",
        media_type="image/png",
      ),
      @provider.LanguageModelContentPart::file_url(
        url="https://example.com/guide.pdf",
        media_type="application/pdf",
        filename="guide.pdf",
      ),
      @provider.LanguageModelContentPart::file_data(
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
          { "type": "input_file", "file_url": "https://example.com/guide.pdf" },
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
test "Open Responses treats image file data as input_image and defaults filenames" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_data(
        data="aW1hZ2U=",
        media_type="image/png",
        filename="ignored.png",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="cGRm",
        media_type="application/pdf",
        filename="",
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
          {
            "type": "input_image",
            "image_url": "data:image/png;base64,aW1hZ2U=",
          },
          {
            "type": "input_file",
            "filename": "data",
            "file_data": "data:application/pdf;base64,cGRm",
          },
        ],
      },
    ],
  })
}

///|
test "Open Responses resolves top-level media types from inline data" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_data(
        data="iVBORw0KGgo=",
        media_type="image/*",
        filename="",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="JVBERg==",
        media_type="application",
        filename="",
      ),
      @provider.LanguageModelContentPart::file_url(
        url="https://example.com/image.png",
        media_type="image",
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
          {
            "type": "input_image",
            "image_url": "data:image/png;base64,iVBORw0KGgo=",
          },
          {
            "type": "input_file",
            "filename": "data",
            "file_data": "data:application/pdf;base64,JVBERg==",
          },
          {
            "type": "input_image",
            "image_url": "https://example.com/image.png",
          },
        ],
      },
    ],
  })
}

///|
test "Open Responses rejects unsupported audio content explicitly" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::audio_data(
        data="YXVkaW8=",
        format="wav",
      ),
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
test "Open Responses rejects provider-reference files explicitly" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_reference(
        reference=@provider.ProviderReference::single(
          provider="openai",
          id="file-openai",
        ),
      ),
    ]),
  ])
  try encode_responses_request("gpt-test", options) catch {
    Failure::Failure(message) =>
      assert_true(message.contains("does not accept file provider references"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected provider-reference content to be rejected")
  }
}

///|
test "Open Responses preserves multimodal tool result content" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::tool_parts("call_1", [
      @provider.LanguageModelContentPart::text("chart attached"),
      @provider.LanguageModelContentPart::image_url(
        "https://example.com/chart.png",
      ),
      @provider.LanguageModelContentPart::file_url(
        url="https://example.com/report.pdf",
        media_type="application/pdf",
        filename="report.pdf",
      ),
    ]),
  ])
  json_inspect(encode_responses_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "input": [
      {
        "type": "function_call_output",
        "call_id": "call_1",
        "output": [
          { "type": "input_text", "text": "chart attached" },
          {
            "type": "input_image",
            "image_url": "https://example.com/chart.png",
          },
          { "type": "input_file", "file_url": "https://example.com/report.pdf" },
        ],
      },
    ],
  })
}

///|
test "encode Open Responses JSON Schema response format" {
  let schema : Json = {
    "type": "object",
    "properties": { "answer": { "type": "string" } },
    "required": ["answer"],
  }
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("answer")],
    response_format=@provider.ResponseFormat::json(
      name="answer_schema",
      description="Structured answer",
      schema~,
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
        "description": "Structured answer",
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
