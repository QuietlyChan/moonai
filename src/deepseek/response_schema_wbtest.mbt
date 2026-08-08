///|
test "DeepSeek response schema validates tools and provider usage fields" {
  let valid : Json = {
    "id": "deepseek-response-1",
    "created": 1700000100,
    "model": "deepseek-chat",
    "choices": [
      {
        "message": {
          "role": "assistant",
          "content": null,
          "reasoning_content": "plan",
          "tool_calls": [
            { "id": null, "function": { "name": "lookup", "arguments": "{}" } },
          ],
        },
        "finish_reason": "tool_calls",
      },
    ],
    "usage": {
      "prompt_tokens": 3,
      "completion_tokens": 5,
      "prompt_cache_hit_tokens": 1,
      "prompt_cache_miss_tokens": 2,
      "total_tokens": 8,
      "completion_tokens_details": { "reasoning_tokens": 4 },
    },
  }
  assert_eq(deepseek_chat_response_validation_error(valid), None)
  assert_true(
    deepseek_chat_response_validation_error({
      "choices": [
        {
          "message": {
            "role": "assistant",
            "tool_calls": [
              {
                "id": "call-1",
                "function": { "name": "lookup", "arguments": 42 },
              },
            ],
          },
          "finish_reason": "tool_calls",
        },
      ],
    })
    is Some(message) &&
    message.contains("arguments"),
  )
  assert_true(
    deepseek_chat_response_validation_error({
      "choices": [],
      "usage": { "prompt_cache_hit_tokens": "one" },
    })
    is Some(message) &&
    message.contains("prompt_cache_hit_tokens"),
  )
}

///|
test "DeepSeek response schema raises structured invalid response errors" {
  let invalid : Json = { "choices": "invalid" }
  try validate_deepseek_chat_response(invalid) catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("Invalid DeepSeek Chat response"))
      assert_eq(data, invalid)
    }
    error => fail("unexpected DeepSeek validation error: \{error}")
  } noraise {
    _ => fail("expected an invalid DeepSeek response")
  }
}
