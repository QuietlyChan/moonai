///|
test "official OpenAI Chat maps reasoning model parameters" {
  let options = @provider.ChatCallOptions::new(
    [
      @provider.LanguageModelMessage::system("Think carefully"),
      @provider.LanguageModelMessage::user("hello"),
    ],
    reasoning_effort=@provider.High,
    max_output_tokens=2048,
    temperature=0.7,
    top_p=0.9,
    frequency_penalty=0.2,
    presence_penalty=0.3,
    provider_options={
      "openai": {
        "parallelToolCalls": false,
        "store": true,
        "textVerbosity": "low",
      },
    },
  )
  json_inspect(encode_openai_chat_request("o1", options, stream=false), content={
    "model": "o1",
    "messages": [
      { "role": "developer", "content": "Think carefully" },
      { "role": "user", "content": "hello" },
    ],
    "parallel_tool_calls": false,
    "max_completion_tokens": 2048,
    "verbosity": "low",
    "store": true,
    "reasoning_effort": "high",
  })
}

///|
test "official OpenAI Chat supports structured output controls" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("answer")],
    response_format=@provider.ResponseFormat::json(
      name="answer",
      description="Structured answer",
      schema={ "type": "object" },
    ),
    provider_options={ "openai": { "strictJsonSchema": true } },
  )
  json_inspect(encode_openai_chat_request("gpt-4o", options, stream=false), content={
    "model": "gpt-4o",
    "messages": [{ "role": "user", "content": "answer" }],
    "response_format": {
      "type": "json_schema",
      "json_schema": {
        "name": "answer",
        "schema": { "type": "object" },
        "strict": true,
        "description": "Structured answer",
      },
    },
  })
}

///|
test "official OpenAI Chat distinguishes omitted and explicit tool choice" {
  let tool = @provider.ToolDefinition::new(
    "lookup",
    { "type": "object" },
    description="Look up a record",
  )
  let omitted = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("find it")],
    tools=[tool],
  )
  json_inspect(encode_openai_chat_request("gpt-4o", omitted, stream=false), content={
    "model": "gpt-4o",
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
  json_inspect(encode_openai_chat_request("gpt-4o", explicit, stream=false), content={
    "model": "gpt-4o",
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
test "official OpenAI Chat rejects PDF URL content" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_url(
        url="https://example.com/guide.pdf",
        media_type="application/pdf",
        filename="guide.pdf",
      ),
    ]),
  ])
  try encode_openai_chat_request("gpt-4o", options, stream=false) catch {
    Failure::Failure(message) =>
      assert_true(message.contains("does not accept PDF file URLs"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected PDF URL content to be rejected")
  }
}

///|
test "official OpenAI Chat resolves provider-reference files" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_reference(
        reference=@provider.ProviderReference::single(
          provider="openai",
          id="file-openai",
        ),
        media_type="application/pdf",
      ),
    ]),
  ])
  json_inspect(encode_openai_chat_request("gpt-4o", options, stream=false), content={
    "model": "gpt-4o",
    "messages": [
      {
        "role": "user",
        "content": [{ "type": "file", "file": { "file_id": "file-openai" } }],
      },
    ],
  })
}

///|
test "official OpenAI Chat resolves wildcard media types for inline files" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_data(
        data="iVBORw0KGgo=",
        media_type="image/*",
        filename="",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="//s=",
        media_type="audio",
        filename="",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="JVBERg==",
        media_type="application/*",
        filename="",
      ),
    ]),
  ])
  json_inspect(encode_openai_chat_request("gpt-4o", options, stream=false), content={
    "model": "gpt-4o",
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
            "input_audio": { "data": "//s=", "format": "mp3" },
          },
          {
            "type": "file",
            "file": {
              "filename": "part-2.pdf",
              "file_data": "data:application/pdf;base64,JVBERg==",
            },
          },
        ],
      },
    ],
  })
}

///|
test "official OpenAI Chat flattens one text-only user part" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::text("Hello"),
    ]),
  ])
  json_inspect(encode_openai_chat_request("gpt-4o", options, stream=false), content={
    "model": "gpt-4o",
    "messages": [{ "role": "user", "content": "Hello" }],
  })
}

///|
test "official OpenAI Chat adds a system prompt cache breakpoint" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::system("You are helpful.", provider_options={
      "openai": { "promptCacheBreakpoint": { "mode": "explicit" } },
    }),
  ])
  json_inspect(encode_openai_chat_request("gpt-4o", options, stream=false), content={
    "model": "gpt-4o",
    "messages": [
      {
        "role": "system",
        "content": [
          {
            "type": "text",
            "text": "You are helpful.",
            "prompt_cache_breakpoint": { "mode": "explicit" },
          },
        ],
      },
    ],
  })
}

///|
test "official OpenAI Chat adds prompt cache breakpoints to user parts" {
  let breakpoint_options : Map[String, Json] = {
    "openai": { "promptCacheBreakpoint": { "mode": "explicit" } },
  }
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::text("Hello").with_provider_options(
        breakpoint_options,
      ),
      @provider.LanguageModelContentPart::image_url(
        "https://example.com/image.png",
      ).with_provider_options(breakpoint_options),
      @provider.LanguageModelContentPart::audio_data(
        data="AAECAw==",
        format="wav",
      ).with_provider_options(breakpoint_options),
      @provider.LanguageModelContentPart::file_reference(
        reference=@provider.ProviderReference::single(
          provider="openai",
          id="file-pdf-123",
        ),
        media_type="application/pdf",
      ).with_provider_options(breakpoint_options),
    ]),
  ])
  json_inspect(encode_openai_chat_request("gpt-4o", options, stream=false), content={
    "model": "gpt-4o",
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "text",
            "text": "Hello",
            "prompt_cache_breakpoint": { "mode": "explicit" },
          },
          {
            "type": "image_url",
            "image_url": { "url": "https://example.com/image.png" },
            "prompt_cache_breakpoint": { "mode": "explicit" },
          },
          {
            "type": "input_audio",
            "input_audio": { "data": "AAECAw==", "format": "wav" },
            "prompt_cache_breakpoint": { "mode": "explicit" },
          },
          {
            "type": "file",
            "file": { "file_id": "file-pdf-123" },
            "prompt_cache_breakpoint": { "mode": "explicit" },
          },
        ],
      },
    ],
  })
}

///|
test "official OpenAI Chat maps imageDetail on image parts" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::image_data(
        data="AAECAw==",
        media_type="image/png",
      ).with_provider_options({ "openai": { "imageDetail": "low" } }),
    ]),
  ])
  json_inspect(encode_openai_chat_request("gpt-4o", options, stream=false), content={
    "model": "gpt-4o",
    "messages": [
      {
        "role": "user",
        "content": [
          {
            "type": "image_url",
            "image_url": {
              "url": "data:image/png;base64,AAECAw==",
              "detail": "low",
            },
          },
        ],
      },
    ],
  })
}

///|
test "official OpenAI Chat preserves assistant and tool text breakpoints" {
  let cached = @provider.LanguageModelContentPart::text("Cached content").with_provider_options({
      "openai": { "promptCacheBreakpoint": { "mode": "explicit" } },
    },
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant_parts([cached]),
    @provider.LanguageModelMessage::tool_parts("call-1", [cached]),
  ])
  json_inspect(encode_openai_chat_request("gpt-4o", options, stream=false), content={
    "model": "gpt-4o",
    "messages": [
      {
        "role": "assistant",
        "content": [
          {
            "type": "text",
            "text": "Cached content",
            "prompt_cache_breakpoint": { "mode": "explicit" },
          },
        ],
      },
      {
        "role": "tool",
        "content": [
          {
            "type": "text",
            "text": "Cached content",
            "prompt_cache_breakpoint": { "mode": "explicit" },
          },
        ],
        "tool_call_id": "call-1",
      },
    ],
  })
}

///|
test "official OpenAI Chat encodes assistant tool-call content parts" {
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
  json_inspect(encode_openai_chat_request("gpt-4o", options, stream=false), content={
    "model": "gpt-4o",
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
test "official OpenAI Chat serializes structured tool results" {
  let result = @provider.LanguageModelToolResult::error_json(
    tool_call_id="call-1",
    tool_name="lookup",
    value={ "message": "not found" },
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::tool_content([
      @provider.LanguageModelContentPart::tool_result(result),
    ]),
  ])
  json_inspect(encode_openai_chat_request("gpt-4o", options, stream=false), content={
    "model": "gpt-4o",
    "messages": [
      {
        "role": "tool",
        "tool_call_id": "call-1",
        "content": "{\"message\":\"not found\"}",
      },
    ],
  })
}
