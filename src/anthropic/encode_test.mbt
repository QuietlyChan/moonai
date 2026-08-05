///|
test "encode Anthropic Messages request" {
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
        {
          "type": "object",
          "properties": { "city": { "type": "string" } },
          "required": ["city"],
        },
        description="Get weather",
        strict=true,
      ),
    ],
    tool_choice=@provider.Required,
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
        "eager_input_streaming": true,
      },
    ],
    "tool_choice": { "type": "any" },
  })
}

///|
test "Anthropic encodes assistant tool-call content parts" {
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
  json_inspect(encode_messages_request("claude-test", options, stream=false), content={
    "model": "claude-test",
    "messages": [
      {
        "role": "assistant",
        "content": [
          {
            "type": "tool_use",
            "id": "call-part",
            "name": "lookup",
            "input": Json::empty_object(),
          },
        ],
      },
    ],
    "max_tokens": 128000,
  })
}

///|
test "Anthropic clamps temperature and omits schema-less JSON format" {
  let high_options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    temperature=1.5,
    response_format=@provider.ResponseFormat::json(),
  )
  json_inspect(
    encode_messages_request("claude-3-haiku-20240307", high_options),
    content={
      "model": "claude-3-haiku-20240307",
      "messages": [
        { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
      ],
      "max_tokens": 4096,
      "stream": true,
      "temperature": 1.0,
    },
  )
}

///|
test "Anthropic resolves namespaced options and protects request fields" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    provider_options={
      "anthropic": {
        "thinking": { "type": "enabled", "budget_tokens": 1024 },
        "stream": false,
        "messages": [],
      },
    },
  )
  json_inspect(
    encode_messages_request(
      "claude-test",
      options,
      provider_name="anthropic.messages",
    ),
    content={
      "model": "claude-test",
      "messages": [
        { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
      ],
      "max_tokens": 129024,
      "stream": true,
      "thinking": { "type": "enabled", "budget_tokens": 1024 },
    },
  )
}

///|
test "Anthropic encodes multimodal user content" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::text("Inspect"),
      @provider.LanguageModelContentPart::image_url(
        "https://example.com/moon.png",
      ),
      @provider.LanguageModelContentPart::image_data(
        data="aW1hZ2U=",
        media_type="image/png",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="cGRm",
        media_type="application/pdf",
        filename="guide.pdf",
      ),
    ]),
  ])
  json_inspect(
    encode_messages_request("claude-3-haiku-20240307", options, stream=false),
    content={
      "model": "claude-3-haiku-20240307",
      "messages": [
        {
          "role": "user",
          "content": [
            { "type": "text", "text": "Inspect" },
            {
              "type": "image",
              "source": { "type": "url", "url": "https://example.com/moon.png" },
            },
            {
              "type": "image",
              "source": {
                "type": "base64",
                "media_type": "image/png",
                "data": "aW1hZ2U=",
              },
            },
            {
              "type": "document",
              "source": {
                "type": "base64",
                "media_type": "application/pdf",
                "data": "cGRm",
              },
              "title": "guide.pdf",
            },
          ],
        },
      ],
      "max_tokens": 4096,
    },
  )
}

///|
test "Anthropic applies message and content-part cache control options" {
  let cached_part = @provider.LanguageModelContentPart::text("cached").with_provider_options({
      "anthropic": { "cacheControl": { "type": "ephemeral" } },
    },
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::system("system", provider_options={
      "anthropic": { "cacheControl": { "type": "ephemeral" } },
    }),
    @provider.LanguageModelMessage::user_parts(
      [@provider.LanguageModelContentPart::text("plain"), cached_part],
      provider_options={
        "anthropic": { "cacheControl": { "type": "ephemeral" } },
      },
    ),
  ])
  json_inspect(
    encode_messages_request("claude-3-haiku-20240307", options, stream=false),
    content={
      "model": "claude-3-haiku-20240307",
      "messages": [
        {
          "role": "user",
          "content": [
            { "type": "text", "text": "plain" },
            {
              "type": "text",
              "text": "cached",
              "cache_control": { "type": "ephemeral" },
            },
          ],
        },
      ],
      "max_tokens": 4096,
      "system": [
        {
          "type": "text",
          "text": "system",
          "cache_control": { "type": "ephemeral" },
        },
      ],
    },
  )
}

///|
test "Anthropic sends signed reasoning blocks back to Messages" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant(
      "answer",
      reasoning_content="thinking first",
      provider_options={ "anthropic": { "signature": "sig_123" } },
    ),
  ])
  json_inspect(
    encode_messages_request("claude-3-7-sonnet", options, stream=false),
    content={
      "model": "claude-3-7-sonnet",
      "messages": [
        {
          "role": "assistant",
          "content": [
            {
              "type": "thinking",
              "thinking": "thinking first",
              "signature": "sig_123",
            },
            { "type": "text", "text": "answer" },
          ],
        },
      ],
      "max_tokens": 4096,
    },
  )
}

///|
test "Anthropic preserves assistant text citations when replaying a prompt" {
  let text = @provider.LanguageModelContentPart::text("The rate stayed steady.").with_provider_options({
      "anthropic": {
        "citations": [
          {
            "type": "web_search_result_location",
            "citedText": "The committee maintained the rate.",
            "url": "https://example.com/fed",
            "title": "Federal Reserve decision",
            "encryptedIndex": "idx-1",
          },
        ],
      },
    },
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant_parts([text]),
  ])
  json_inspect(
    encode_messages_request("claude-3-7-sonnet", options, stream=false),
    content={
      "model": "claude-3-7-sonnet",
      "messages": [
        {
          "role": "assistant",
          "content": [
            {
              "type": "text",
              "text": "The rate stayed steady.",
              "citations": [
                {
                  "type": "web_search_result_location",
                  "cited_text": "The committee maintained the rate.",
                  "url": "https://example.com/fed",
                  "title": "Federal Reserve decision",
                  "encrypted_index": "idx-1",
                },
              ],
            },
          ],
        },
      ],
      "max_tokens": 4096,
    },
  )
}

///|
test "Anthropic resolves wildcard media and text documents" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_data(
        data="iVBORw0KGgo=",
        media_type="image/*",
        filename="",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="JVBERg==",
        media_type="application/*",
        filename="guide.pdf",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="TW9vbkJpdA==",
        media_type="text/plain",
        filename="readme.txt",
      ),
      @provider.LanguageModelContentPart::file_url(
        url="https://example.com/readme.txt",
        media_type="text/plain",
        filename="remote.txt",
      ),
    ]),
  ])
  json_inspect(
    encode_messages_request("claude-3-haiku-20240307", options, stream=false),
    content={
      "model": "claude-3-haiku-20240307",
      "messages": [
        {
          "role": "user",
          "content": [
            {
              "type": "image",
              "source": {
                "type": "base64",
                "media_type": "image/png",
                "data": "iVBORw0KGgo=",
              },
            },
            {
              "type": "document",
              "source": {
                "type": "base64",
                "media_type": "application/pdf",
                "data": "JVBERg==",
              },
              "title": "guide.pdf",
            },
            {
              "type": "document",
              "source": {
                "type": "text",
                "media_type": "text/plain",
                "data": "MoonBit",
              },
              "title": "readme.txt",
            },
            {
              "type": "document",
              "source": {
                "type": "url",
                "url": "https://example.com/readme.txt",
              },
              "title": "remote.txt",
            },
          ],
        },
      ],
      "max_tokens": 4096,
    },
  )
}

///|
test "Anthropic maps camel-case options to Messages wire fields" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    provider_options={
      "anthropic": {
        "thinking": { "type": "adaptive", "display": "summarized" },
        "effort": "high",
        "disableParallelToolUse": true,
        "metadata": { "userId": "opaque-user" },
        "mcpServers": [
          {
            "type": "url",
            "name": "docs",
            "url": "https://mcp.example.com",
            "authorizationToken": "token",
            "toolConfiguration": { "enabled": true, "allowedTools": ["search"] },
          },
        ],
        "taskBudget": { "type": "tokens", "total": 20000 },
        "speed": "fast",
        "inferenceGeo": "us",
      },
    },
  )
  json_inspect(
    encode_messages_request("claude-sonnet-4-6", options, stream=false),
    content={
      "model": "claude-sonnet-4-6",
      "messages": [
        { "role": "user", "content": [{ "type": "text", "text": "hello" }] },
      ],
      "max_tokens": 128000,
      "thinking": { "type": "adaptive", "display": "summarized" },
      "output_config": {
        "effort": "high",
        "task_budget": { "type": "tokens", "total": 20000 },
      },
      "metadata": { "user_id": "opaque-user" },
      "mcp_servers": [
        {
          "type": "url",
          "name": "docs",
          "url": "https://mcp.example.com",
          "authorization_token": "token",
          "tool_configuration": { "enabled": true, "allowed_tools": ["search"] },
        },
      ],
      "speed": "fast",
      "inference_geo": "us",
    },
  )
}

///|
test "Anthropic prompt options resolve the custom provider namespace" {
  let cached = @provider.LanguageModelContentPart::text("cached").with_provider_options({
      "localClaude": { "cacheControl": { "type": "ephemeral" } },
    },
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::system("system", provider_options={
      "localClaude": { "cacheControl": { "type": "ephemeral" } },
    }),
    @provider.LanguageModelMessage::user_parts([cached]),
    @provider.LanguageModelMessage::assistant_parts(
      [
        @provider.LanguageModelContentPart::text("cited").with_provider_options({
            "localClaude": {
              "citations": [
                {
                  "type": "web_search_result_location",
                  "citedText": "source text",
                  "url": "https://example.com/source",
                  "title": "Source",
                },
              ],
            },
          },
        ),
      ],
      reasoning_content="signed thought",
      provider_options={ "localClaude": { "signature": "sig-custom" } },
    ),
  ])
  json_inspect(
    encode_messages_request(
      "claude-sonnet-4-6",
      options,
      stream=false,
      provider_name="local-claude.messages",
    ),
    content={
      "model": "claude-sonnet-4-6",
      "messages": [
        {
          "role": "user",
          "content": [
            {
              "type": "text",
              "text": "cached",
              "cache_control": { "type": "ephemeral" },
            },
          ],
        },
        {
          "role": "assistant",
          "content": [
            {
              "type": "thinking",
              "thinking": "signed thought",
              "signature": "sig-custom",
            },
            {
              "type": "text",
              "text": "cited",
              "citations": [
                {
                  "type": "web_search_result_location",
                  "cited_text": "source text",
                  "url": "https://example.com/source",
                  "title": "Source",
                },
              ],
            },
          ],
        },
      ],
      "max_tokens": 128000,
      "system": [
        {
          "type": "text",
          "text": "system",
          "cache_control": { "type": "ephemeral" },
        },
      ],
    },
  )
}
