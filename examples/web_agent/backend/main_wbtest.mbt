///|
test "chat request accepts message history" {
  let messages = parse_chat_messages({
    "messages": [
      { "role": "user", "content": "hello" },
      { "role": "assistant", "content": "hi" },
      { "role": "user", "content": "calculate 2 + 2" },
    ],
  })
  assert_eq(messages.length(), 3)
  assert_true(messages[0].role is @provider_utils.ModelUser)
  assert_true(messages[1].role is @provider_utils.ModelAssistant)
}

///|
test "chat request accepts prompt shorthand" {
  let messages = parse_chat_messages({ "prompt": "hello" })
  assert_eq(messages.length(), 1)
  assert_true(messages[0].role is @provider_utils.ModelUser)
}

///|
test "chat request rejects assistant as final message" {
  try {
    ignore(
      parse_chat_messages({
        "messages": [{ "role": "assistant", "content": "done" }],
      }),
    )
    fail("expected parser to reject the request")
  } catch {
    error => assert_true("\{error}".contains("final message"))
  }
}

///|
test "AI SDK request reads text parts from UI messages" {
  let messages = parse_ui_chat_messages({
    "id": "chat-1",
    "trigger": "submit-message",
    "messageId": Json::null(),
    "messages": [
      {
        "id": "user-1",
        "role": "user",
        "parts": [{ "type": "text", "text": "hello" }],
      },
      {
        "id": "assistant-1",
        "role": "assistant",
        "parts": [{ "type": "text", "text": "hi" }],
      },
      {
        "id": "user-2",
        "role": "user",
        "parts": [
          { "type": "data-client", "data": { "ignored": true } },
          { "type": "text", "text": "calculate 2 + 2" },
        ],
      },
    ],
  })
  assert_eq(messages.length(), 3)
  assert_true(messages[0].role is @provider_utils.ModelUser)
  assert_true(messages[1].role is @provider_utils.ModelAssistant)
  assert_true(messages[2].role is @provider_utils.ModelUser)
}

///|
test "AI SDK regenerate removes the selected assistant message" {
  let messages = parse_ui_chat_messages({
    "id": "chat-1",
    "trigger": "regenerate-message",
    "messageId": "assistant-1",
    "messages": [
      {
        "id": "user-1",
        "role": "user",
        "parts": [{ "type": "text", "text": "hello" }],
      },
      {
        "id": "assistant-1",
        "role": "assistant",
        "parts": [{ "type": "text", "text": "old answer" }],
      },
    ],
  })
  assert_eq(messages.length(), 1)
  assert_true(messages[0].role is @provider_utils.ModelUser)
}

///|
test "AI SDK SSE events use data frames" {
  assert_eq(
    sse_event({ "type": "text-delta", "id": "text-1", "delta": "hello" }),
    "data: {\"type\":\"text-delta\",\"id\":\"text-1\",\"delta\":\"hello\"}\n\n",
  )
}

///|
test "standalone frontend assets are embedded" {
  assert_true(embedded_frontend("index.html").unwrap().contains("MoonAI Agent"))
  assert_true(embedded_frontend("app.js").unwrap().contains("/api/chat/stream"))
  assert_true(embedded_frontend("styles.css").unwrap().contains(".workspace"))
}
