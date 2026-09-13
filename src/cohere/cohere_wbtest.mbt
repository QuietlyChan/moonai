///|
test "cohere finish reason mapping covers UPPER raw values" {
  assert_eq(cohere_map_finish_reason(Some("COMPLETE")), {
    unified: @provider.V4FinishStop,
    raw: Some("COMPLETE"),
  })
  assert_eq(cohere_map_finish_reason(Some("MAX_TOKENS")), {
    unified: @provider.V4FinishLength,
    raw: Some("MAX_TOKENS"),
  })
  assert_eq(cohere_map_finish_reason(Some("TOOL_CALL")), {
    unified: @provider.V4FinishToolCalls,
    raw: Some("TOOL_CALL"),
  })
  assert_eq(cohere_map_finish_reason(None), {
    unified: @provider.V4FinishOther,
    raw: None,
  })
}

///|
test "cohere usage prefers tokens totals" {
  let usage = cohere_usage(
    Some({
      "tokens": { "input_tokens": 12, "output_tokens": 34 },
      "billed_units": { "input_tokens": 10, "output_tokens": 30 },
    }),
  )
  assert_eq(usage.input_tokens.total, Some(12))
  assert_eq(usage.output_tokens.total, Some(34))
  assert_eq(cohere_usage(None).input_tokens.total, None)
}

///|
test "cohere tool call fields extraction" {
  assert_eq(
    cohere_tool_call_fields({
      "id": "t1",
      "function": { "name": "search", "arguments": "{}" },
    }),
    ("t1", "search", "{}"),
  )
  assert_eq(cohere_tool_call_fields({}), ("", "", ""))
}

///|
test "cohere error message resolves flat payloads" {
  assert_eq(
    cohere_error_to_message({ "message": "invalid request" }),
    Some("invalid request"),
  )
  assert_eq(cohere_error_to_message({ "code": 1 }), None)
}
