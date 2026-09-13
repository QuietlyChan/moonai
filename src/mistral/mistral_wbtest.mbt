///|
test "mistral finish reason mapping" {
  assert_eq(mistral_map_finish_reason(Some("tool_calls")), {
    unified: @provider.V4FinishToolCalls,
    raw: Some("tool_calls"),
  })
  assert_eq(mistral_map_finish_reason(Some("mysterious")), {
    unified: @provider.V4FinishOther,
    raw: Some("mysterious"),
  })
}

///|
test "mistral thinking payload flattening" {
  assert_eq(mistral_thinking_text(Json::string("direct")), Some("direct"))
  assert_eq(
    mistral_thinking_text([
      { "type": "text", "text": "a" },
      { "type": "text", "text": "b" },
    ]),
    Some("ab"),
  )
  assert_eq(mistral_thinking_text(Json::number(1)), None)
}

///|
test "mistral reasoning effort whitelist follows magistral ids" {
  assert_true(mistral_supports_reasoning_effort("magistral-medium-latest"))
  assert_false(mistral_supports_reasoning_effort("mistral-large-latest"))
}

///|
test "mistral error message resolves flat payloads" {
  assert_eq(
    mistral_error_to_message({ "message": "boom", "code": 1 }),
    Some("boom"),
  )
  assert_eq(mistral_error_to_message({ "code": 1 }), None)
}
