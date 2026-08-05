///|
test "DeepSeek reports unsupported topK" {
  let prepared = prepare_deepseek_request(
    "deepseek-chat",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      top_k=40.0,
    ),
    "deepseek.chat",
    false,
    true,
    false,
  )
  assert_eq(prepared.warnings.length(), 1)
  assert_true(prepared.warnings[0] is @provider.Unsupported(feature="topK", ..))
  assert_false(prepared.body.stringify().contains("top_k"))
}

///|
test "DeepSeek reports lossy top-level reasoning mappings" {
  let minimal = prepare_deepseek_request(
    "deepseek-reasoner",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      reasoning_effort=@provider.Minimal,
    ),
    "deepseek.chat",
    false,
    true,
    false,
  )
  json_inspect(minimal.body, content={
    "model": "deepseek-reasoner",
    "messages": [{ "role": "user", "content": "hello" }],
    "thinking": { "type": "enabled" },
    "reasoning_effort": "low",
  })
  assert_true(
    minimal.warnings.any(warning => {
      warning
      is @provider.Compatibility(
        feature="reasoning",
        details="reasoning \"minimal\" is not directly supported by this model; mapped to effort \"low\"."
      )
    }),
  )
  let xhigh = prepare_deepseek_request(
    "deepseek-reasoner",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      reasoning_effort=@provider.XHigh,
    ),
    "deepseek.chat",
    false,
    true,
    false,
  )
  assert_true(xhigh.body.stringify().contains("\"reasoning_effort\":\"max\""))
  assert_true(
    xhigh.warnings.any(warning => {
      warning
      is @provider.Compatibility(
        feature="reasoning",
        details="reasoning \"xhigh\" is not directly supported by this model; mapped to effort \"max\"."
      )
    }),
  )
}

///|
test "DeepSeek keeps text content wrapped in provider options" {
  let text = @provider.LanguageModelContentPart::text("cached text").with_provider_options({
      "deepseek": { "cacheControl": { "type": "ephemeral" } },
    },
  )
  let prepared = prepare_deepseek_request(
    "deepseek-chat",
    @provider.ChatCallOptions::new([
      @provider.LanguageModelMessage::user_parts([text]),
    ]),
    "deepseek.chat",
    false,
    true,
    false,
  )
  json_inspect(prepared.body, content={
    "model": "deepseek-chat",
    "messages": [{ "role": "user", "content": "cached text" }],
  })
  assert_false(
    prepared.warnings.any(warning => {
      warning is @provider.Unsupported(feature="multimodal message part", ..)
    }),
  )
}
