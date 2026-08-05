///|
test "encode OpenAI-compatible streaming request" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("weather")],
    tools=[
      @provider.ToolDefinition::new(
        "get_weather",
        {
          "type": "object",
          "properties": { "city": { "type": "string" } },
          "required": ["city"],
        },
        description="Get weather",
        strict=true,
      ),
    ],
    response_format=@provider.ResponseFormat::json(),
    temperature=0.2,
    frequency_penalty=-0.1,
    presence_penalty=0.3,
    seed=42,
  )
  json_inspect(encode_chat_request("gpt-test", options, include_usage=true), content={
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
    "response_format": { "type": "json_object" },
  })
}

///|
test "OpenAI-compatible omits streaming usage options by default" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user("hello"),
  ])
  assert_false(
    encode_chat_request("gpt-test", options)
    .stringify()
    .contains("stream_options"),
  )
}

///|
test "OpenAI-compatible preserves an explicit automatic tool choice" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("weather")],
    tools=[
      @provider.ToolDefinition::new(
        "get_weather",
        { "type": "object" },
        description="Get weather",
      ),
    ],
    tool_choice=@provider.Auto,
  )
  json_inspect(encode_chat_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "messages": [{ "role": "user", "content": "weather" }],
    "tools": [
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get weather",
          "parameters": { "type": "object" },
        },
      },
    ],
    "tool_choice": "auto",
  })
}

///|
test "encode OpenAI-compatible non-streaming request" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user("hello"),
  ])
  json_inspect(encode_chat_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "messages": [{ "role": "user", "content": "hello" }],
  })
}

///|
test "OpenAI-compatible serializes structured tool results" {
  let result = @provider.LanguageModelToolResult::execution_denied(
    tool_call_id="call-1",
    tool_name="lookup",
    reason="cancelled",
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::tool_content([
      @provider.LanguageModelContentPart::tool_result(result),
    ]),
  ])
  json_inspect(encode_chat_request("compatible", options, stream=false), content={
    "model": "compatible",
    "messages": [
      { "role": "tool", "tool_call_id": "call-1", "content": "cancelled" },
    ],
  })
}

///|
test "OpenAI-compatible flattens one text part and uses its metadata" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts(
      [
        @provider.LanguageModelContentPart::text("hello").with_provider_options({
            "openaiCompatible": { "contentLevel": true, "sharedKey": "content" },
          },
        ),
      ],
      provider_options={
        "openaiCompatible": { "messageLevel": true, "sharedKey": "message" },
      },
    ),
  ])
  json_inspect(encode_chat_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "messages": [
      {
        "role": "user",
        "content": "hello",
        "contentLevel": true,
        "sharedKey": "content",
      },
    ],
  })
}

///|
test "OpenAI-compatible keeps message and multipart metadata at their layers" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts(
      [
        @provider.LanguageModelContentPart::text("describe").with_provider_options({
            "openaiCompatible": { "textPartLevel": "text" },
          },
        ),
        @provider.LanguageModelContentPart::image_url(
          "https://example.com/image.png",
        ).with_provider_options({
          "openaiCompatible": { "imagePartLevel": "image" },
        }),
      ],
      provider_options={
        "openaiCompatible": { "messageLevel": "message" },
        "anotherProvider": { "ignored": true },
      },
    ),
  ])
  json_inspect(encode_chat_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "messages": [
      {
        "role": "user",
        "content": [
          { "type": "text", "text": "describe", "textPartLevel": "text" },
          {
            "type": "image_url",
            "image_url": { "url": "https://example.com/image.png" },
            "imagePartLevel": "image",
          },
        ],
        "messageLevel": "message",
      },
    ],
  })
}

///|
test "OpenAI-compatible assistant tool calls re-encode thought signatures" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant("", tool_calls=[
      @provider.ToolCall::new(id="call-1", name="lookup", arguments="{}", provider_metadata={
        "google": { "thoughtSignature": "signature-1" },
      }),
    ]),
  ])
  json_inspect(
    encode_chat_request("gemini-compatible", options, stream=false),
    content={
      "model": "gemini-compatible",
      "messages": [
        {
          "role": "assistant",
          "content": null,
          "tool_calls": [
            {
              "id": "call-1",
              "type": "function",
              "function": { "name": "lookup", "arguments": "{}" },
              "extra_content": {
                "google": { "thought_signature": "signature-1" },
              },
            },
          ],
        },
      ],
    },
  )
}

///|
test "OpenAI-compatible encodes assistant tool-call content parts" {
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
  json_inspect(encode_chat_request("compatible", options, stream=false), content={
    "model": "compatible",
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
  })
}

///|
test "OpenAI-compatible separates assistant and tool-call metadata" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant(
      "checking",
      tool_calls=[
        @provider.ToolCall::new(id="call-1", name="lookup", arguments="{}", provider_metadata={
          "openaiCompatible": {
            "toolPriority": "critical",
            "sharedKey": "tool",
          },
          "google": { "thoughtSignature": "signature-1" },
        }),
      ],
      provider_options={
        "openaiCompatible": {
          "messagePriority": "high",
          "sharedKey": "message",
        },
      },
    ),
  ])
  json_inspect(encode_chat_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "messages": [
      {
        "role": "assistant",
        "content": "checking",
        "tool_calls": [
          {
            "id": "call-1",
            "type": "function",
            "function": { "name": "lookup", "arguments": "{}" },
            "toolPriority": "critical",
            "sharedKey": "tool",
            "extra_content": {
              "google": { "thought_signature": "signature-1" },
            },
          },
        ],
        "messagePriority": "high",
        "sharedKey": "message",
      },
    ],
  })
}

///|
test "OpenAI-compatible structured output falls back unless enabled" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("answer")],
    response_format=@provider.ResponseFormat::json(name="answer_schema", schema={
      "type": "object",
    }),
  )
  json_inspect(encode_chat_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "messages": [{ "role": "user", "content": "answer" }],
    "response_format": { "type": "json_object" },
  })
}

///|
test "OpenAI-compatible namespaced options map typed fields and protect transport" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    reasoning_effort=@provider.Low,
    provider_options={
      "localTest": {
        "reasoningEffort": "high",
        "textVerbosity": "low",
        "user": "user-1",
        "stream": false,
      },
    },
  )
  json_inspect(
    encode_chat_request(
      "gpt-test",
      options,
      provider_name="local-test.chat",
      include_usage=true,
    ),
    content={
      "model": "gpt-test",
      "messages": [{ "role": "user", "content": "hello" }],
      "stream": true,
      "stream_options": { "include_usage": true },
      "user": "user-1",
      "reasoning_effort": "high",
      "verbosity": "low",
    },
  )
}

///|
test "OpenAI-compatible merges generic and provider-specific option layers" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    provider_options={
      "openaiCompatible": { "user": "generic-user", "textVerbosity": "low" },
      "localTest": {
        "user": "custom-user",
        "reasoningEffort": "high",
        "vendorFlag": true,
      },
    },
  )
  json_inspect(
    encode_chat_request(
      "gpt-test",
      options,
      provider_name="local-test.chat",
      include_usage=true,
    ),
    content={
      "model": "gpt-test",
      "messages": [{ "role": "user", "content": "hello" }],
      "stream": true,
      "stream_options": { "include_usage": true },
      "user": "custom-user",
      "reasoning_effort": "high",
      "verbosity": "low",
      "vendorFlag": true,
    },
  )
}

///|
test "encode OpenAI-compatible multimodal content parts" {
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
      @provider.LanguageModelContentPart::audio_data(
        data="YXVkaW8=",
        format="wav",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="ZmlsZQ==",
        media_type="application/pdf",
        filename="guide.pdf",
      ),
    ]),
  ])
  json_inspect(
    encode_chat_request(
      "gpt-test",
      options,
      stream=false,
      supports_structured_outputs=true,
    ),
    content={
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
    },
  )
}

///|
test "OpenAI-compatible handles URL-backed files like AI SDK" {
  let text_options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_url(
        url="https://example.com/readme.txt",
        media_type="text/plain",
        filename="readme.txt",
      ),
    ]),
  ])
  json_inspect(encode_chat_request("gpt-test", text_options, stream=false), content={
    "model": "gpt-test",
    "messages": [
      {
        "role": "user",
        "content": [
          { "type": "text", "text": "https://example.com/readme.txt" },
        ],
      },
    ],
  })
  let pdf_options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_url(
        url="https://example.com/guide.pdf",
        media_type="application/pdf",
        filename="guide.pdf",
      ),
    ]),
  ])
  try encode_chat_request("gpt-test", pdf_options, stream=false) catch {
    Failure::Failure(message) =>
      assert_true(message.contains("does not accept PDF file URLs"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected PDF URL content to be rejected")
  }
}

///|
test "OpenAI-compatible resolves wildcard media types for inline files" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_data(
        data="iVBORw0KGgo=",
        media_type="image/*",
        filename="",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="UklGRgAAAABXQVZF",
        media_type="audio",
        filename="",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="JVBERg==",
        media_type="application/*",
        filename="",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="TW9vbkJpdA==",
        media_type="text/plain",
        filename="readme.txt",
      ),
    ]),
  ])
  json_inspect(encode_chat_request("gpt-test", options, stream=false), content={
    "model": "gpt-test",
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "image_url",
            "image_url": { "url": "data:image/png;base64,iVBORw0KGgo=" },
          },
          {
            "type": "input_audio",
            "input_audio": { "data": "UklGRgAAAABXQVZF", "format": "wav" },
          },
          {
            "type": "file",
            "file": {
              "filename": "document.pdf",
              "file_data": "data:application/pdf;base64,JVBERg==",
            },
          },
          { "type": "text", "text": "MoonBit" },
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
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("answer")],
    response_format=@provider.ResponseFormat::json(
      name="answer_schema",
      description="Structured answer",
      schema~,
    ),
  )
  json_inspect(
    encode_chat_request(
      "gpt-test",
      options,
      stream=false,
      supports_structured_outputs=true,
    ),
    content={
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
          "description": "Structured answer",
        },
      },
    },
  )
}

///|
test "OpenAI-compatible capability switches expose topK and omit unsupported frequency penalty" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    top_k=20.0,
    frequency_penalty=0.4,
  )
  json_inspect(
    encode_chat_request(
      "qwen-test",
      options,
      stream=false,
      supports_top_k=true,
      supports_frequency_penalty=false,
    ),
    content={
      "model": "qwen-test",
      "messages": [{ "role": "user", "content": "hello" }],
      "top_k": 20,
    },
  )
}

///|
test "OpenAI-compatible chat extensions use OpenAI wire names" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    provider_options={
      "localTest": {
        "parallelToolCalls": false,
        "logitBias": { "42": -1.0 },
        "customOption": "kept",
      },
    },
  )
  json_inspect(
    encode_chat_request(
      "local-model",
      options,
      stream=false,
      provider_name="local-test.chat",
    ),
    content={
      "model": "local-model",
      "messages": [{ "role": "user", "content": "hello" }],
      "parallel_tool_calls": false,
      "logit_bias": { "42": -1.0 },
      "customOption": "kept",
    },
  )
}

///|
test "OpenAI-compatible Chat rejects provider-reference files explicitly" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_reference(
        reference=@provider.ProviderReference::single(
          provider="openaiCompatible",
          id="file-compatible",
        ),
      ),
    ]),
  ])
  try encode_chat_request("model", options) catch {
    Failure::Failure(message) =>
      assert_true(message.contains("does not accept file provider references"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected provider-reference content to be rejected")
  }
}
