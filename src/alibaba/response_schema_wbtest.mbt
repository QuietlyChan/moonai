///|
test "Alibaba response schema requires choice indexes and complete usage" {
  let valid : Json = {
    "id": "ali-response-1",
    "created": 1700000200,
    "model": "qwen-plus",
    "choices": [
      {
        "index": 0,
        "message": { "role": "assistant", "content": "answer" },
        "finish_reason": "stop",
      },
    ],
    "usage": { "prompt_tokens": 1, "completion_tokens": 2, "total_tokens": 3 },
  }
  assert_eq(validate_alibaba_chat_response(valid), None)
  assert_true(
    validate_alibaba_chat_response({
      "choices": [
        {
          "message": { "role": "assistant", "content": "answer" },
          "finish_reason": "stop",
        },
      ],
    })
    is Some(message) &&
    message.contains("index"),
  )
  assert_true(
    validate_alibaba_chat_response({
      "choices": [
        {
          "index": 0,
          "message": { "role": "assistant", "content": "answer" },
          "finish_reason": "stop",
        },
      ],
      "usage": { "prompt_tokens": 1, "completion_tokens": 2 },
    })
    is Some(message) &&
    message.contains("total_tokens"),
  )
}

///|
test "Alibaba stream schema matches its partial tool delta contract" {
  assert_eq(
    validate_alibaba_chat_chunk({
      "choices": [
        {
          "index": 0,
          "delta": {
            "role": "assistant",
            "tool_calls": [{ "index": 0, "id": "call-1", "type": "function" }],
          },
          "finish_reason": null,
        },
      ],
      "usage": null,
    }),
    None,
  )
  assert_true(
    validate_alibaba_chat_chunk({
      "choices": [
        { "index": 0, "delta": { "role": "" }, "finish_reason": null },
      ],
    })
    is Some(message) &&
    message.contains("role"),
  )
}
