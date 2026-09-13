///|
test "cerebras body transform renames wire fields" {
  let body : Json = {
    "model": "gpt-oss-120b",
    "max_tokens": 1024,
    "parallelToolCalls": true,
    "topLogprobs": 5,
    "logitBias": { "42": 10 },
    "serviceTier": "priority",
    "reasoningFormat": "parsed",
    "promptCacheKey": "cache-1",
  }
  let transformed = cerebras_transform_request_body(body)
  assert_true(
    transformed
    is {
      "model": "gpt-oss-120b",
      "max_completion_tokens": 1024,
      "parallel_tool_calls": true,
      "top_logprobs": 5,
      "service_tier": "priority",
      "reasoning_format": "parsed",
      "prompt_cache_key": "cache-1",
      ..
    },
  )
  assert_true(transformed.stringify().contains("logit_bias"))
  assert_false(transformed.stringify().contains("max_tokens\""))
}

///|
test "cerebras rewrites assistant reasoning_content into reasoning" {
  let body : Json = {
    "messages": [
      { "role": "user", "content": "hi" },
      {
        "role": "assistant",
        "content": "answer",
        "reasoning_content": "because",
      },
    ],
  }
  let transformed = cerebras_transform_request_body(body)
  assert_true(
    transformed
    is {
      "messages": [
        { "role": "user", "content": "hi", .. },
        { "role": "assistant", "content": "answer", "reasoning": "because", .. },
      ],
      ..
    },
  )
}

///|
test "cerebras keeps explicit reasoning over replayed reasoning_content" {
  let body : Json = {
    "messages": [
      { "role": "assistant", "reasoning": "kept", "reasoning_content": "stale" },
    ],
  }
  let transformed = cerebras_transform_request_body(body)
  assert_true(
    transformed
    is {
      "messages": [{ "role": "assistant", "reasoning": "kept", .. }, ..],
      ..
    },
  )
}

///|
test "cerebras error message resolves the flat payload" {
  assert_eq(
    cerebras_error_to_message({
      "message": "boom",
      "type": "invalid_request_error",
    }),
    Some("boom"),
  )
  assert_eq(
    cerebras_error_to_message({ "type": "invalid_request_error" }),
    None,
  )
}
