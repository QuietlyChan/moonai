///|
test "gateway finish reason maps unified and raw" {
  assert_eq(gateway_finish_reason(Some({ "unified": "stop", "raw": "stop" })), {
    unified: @provider.V4FinishStop,
    raw: Some("stop"),
  })
  assert_eq(
    gateway_finish_reason(
      Some({ "unified": "tool-calls", "raw": "tool_calls" }),
    ),
    { unified: @provider.V4FinishToolCalls, raw: Some("tool_calls"), },
  )
  assert_eq(gateway_finish_reason(None), {
    unified: @provider.V4FinishOther,
    raw: None,
  })
}

///|
test "gateway usage decodes v4 usage json" {
  let usage = gateway_usage(
    Some({
      "inputTokens": { "total": 10, "cacheRead": 4 },
      "outputTokens": { "total": 20, "reasoning": 5 },
    }),
  )
  assert_eq(usage.input_tokens.total, Some(10))
  assert_eq(usage.input_tokens.no_cache, Some(6))
  assert_eq(usage.input_tokens.cache_read, Some(4))
  assert_eq(usage.output_tokens.total, Some(20))
  assert_eq(usage.output_tokens.text, Some(15))
  assert_eq(usage.output_tokens.reasoning, Some(5))
}

///|
test "gateway warnings forwarding keeps server warnings (#20675)" {
  let warnings = gateway_decode_warnings(
    Some([
      { "type": "unsupported", "feature": "topK", "details": "not supported" },
    ]),
  )
  assert_eq(warnings.length(), 1)
  assert_true(warnings[0] is @provider.Warning::Unsupported(feature="topK", ..))
  assert_eq(gateway_decode_warnings(None).length(), 0)
}

///|
test "gateway error message resolves nested payloads" {
  assert_eq(
    gateway_error_to_message({ "error": { "message": "model not found" } }),
    Some("model not found"),
  )
  assert_eq(gateway_error_to_message({ "code": 404 }), None)
}

///|
test "gateway spend report query and origin derivation" {
  let query = gateway_spend_query(params={
    start_date: "2026-09-01",
    end_date: "2026-09-07",
    group_by: Some(SpendModel),
    date_part_hour: None,
    user_id: None,
    model: Some("anthropic/claude-sonnet-4.5"),
    provider: None,
    credential_type: Some("byok"),
    tags: Some(["team-a", "team-b"]),
  })
  assert_true(query.contains("start_date=2026-09-01"))
  assert_true(query.contains("end_date=2026-09-07"))
  assert_true(query.contains("group_by=model"))
  assert_true(query.contains("model=anthropic/claude-sonnet-4.5"))
  assert_true(query.contains("credential_type=byok"))
  assert_true(query.contains("tags=team-a,team-b"))
  assert_eq(
    gateway_spend_origin(base_url="https://ai-gateway.vercel.sh/v4/ai"),
    Some("https://ai-gateway.vercel.sh"),
  )
}

///|
test "gateway spend report row decode maps snake_case fields" {
  let row = decode_gateway_spend_row({
    "model": "openai/gpt-5.2",
    "total_cost": 0.42,
    "input_tokens": 100,
    "output_tokens": 50,
  })
  assert_eq(row.model, Some("openai/gpt-5.2"))
  assert_eq(row.total_cost, 0.42)
  assert_eq(row.input_tokens, Some(100))
}
