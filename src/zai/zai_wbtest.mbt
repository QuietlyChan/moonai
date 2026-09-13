///|
test "zai request body transform maps z.ai fields and drops unsupported settings" {
  let body : Json = {
    "model": "glm-5",
    "messages": [],
    "doSample": false,
    "thinking": { "type": "enabled", "clearThinking": true },
    "toolStream": true,
    "requestId": "req-0001",
    "userId": "user-0001",
    "frequency_penalty": 0.5,
    "presence_penalty": 0.5,
    "seed": 42,
    "user": "someone",
    "verbosity": "low",
  }
  let transformed = zai_transform_request_body(body)
  assert_true(
    transformed
    is {
      "model": "glm-5",
      "do_sample": false,
      "thinking": { "type": "enabled", "clear_thinking": true, .. },
      "tool_stream": true,
      "request_id": "req-0001",
      "user_id": "user-0001",
      ..
    },
  )
  let wire = transformed.stringify()
  assert_false(wire.contains("frequency_penalty"))
  assert_false(wire.contains("presence_penalty"))
  assert_false(wire.contains("verbosity"))
  assert_false(wire.contains("\"seed\""))
  assert_false(wire.contains("\"user\""))
}

///|
test "zai maps provider finish reasons onto the unified scale" {
  assert_eq(
    zai_map_finish_reason({
      unified: @provider.V4FinishOther,
      raw: Some("sensitive"),
    }),
    { unified: @provider.V4FinishContentFilter, raw: Some("sensitive"), },
  )
  assert_eq(
    zai_map_finish_reason({
      unified: @provider.V4FinishOther,
      raw: Some("model_context_window_exceeded"),
    }),
    {
      unified: @provider.V4FinishLength,
      raw: Some("model_context_window_exceeded"),
    },
  )
  assert_eq(
    zai_map_finish_reason({
      unified: @provider.V4FinishOther,
      raw: Some("network_error"),
    }),
    { unified: @provider.V4FinishError, raw: Some("network_error"), },
  )
  assert_eq(
    zai_map_finish_reason({
      unified: @provider.V4FinishStop,
      raw: Some("stop"),
    }),
    { unified: @provider.V4FinishStop, raw: Some("stop"), },
  )
}

///|
test "zai error message resolves flat and nested payloads" {
  assert_eq(
    zai_error_to_message({ "code": 1003, "message": "boom" }),
    Some("boom"),
  )
  assert_eq(
    zai_error_to_message({
      "error": { "code": "1003", "message": "nested boom" },
    }),
    Some("nested boom"),
  )
  assert_eq(zai_error_to_message({ "error": {} }), None)
  assert_eq(zai_error_to_message("oops"), None)
}

///|
test "zai warns for unsupported sampling settings and restricts tool choice" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([]),
    tool_choice=@provider.V4ToolChoiceRequired,
    frequency_penalty=0.5,
    presence_penalty=0.5,
    seed=42,
  )
  let (effective, warnings) = zai_prepare_call_options(options)
  assert_eq(effective.tool_choice, None)
  assert_eq(effective.frequency_penalty, Some(0.5))
  assert_eq(warnings.length(), 4)
  assert_true(
    warnings[0]
    is @provider.Warning::Unsupported(feature="frequencyPenalty", ..),
  )
  assert_true(
    warnings[1] is @provider.Warning::Unsupported(feature="presencePenalty", ..),
  )
  assert_true(warnings[2] is @provider.Warning::Unsupported(feature="seed", ..))
  assert_true(
    warnings[3]
    is @provider.Warning::Unsupported(
      feature="toolChoice required",
      details="Z.AI currently supports only automatic tool selection."
    ),
  )
  let none_options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([]),
    tool_choice=@provider.V4ToolChoiceNone,
  )
  let (none_effective, none_warnings) = zai_prepare_call_options(none_options)
  assert_eq(none_effective.tool_choice, None)
  assert_eq(none_effective.tools.length(), 0)
  assert_eq(none_warnings, [])
}
