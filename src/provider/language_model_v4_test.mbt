///|
test "V4 usage keeps cache and reasoning counters" {
  let usage = Usage::new(
    input_tokens=120,
    output_tokens=30,
    total_tokens=150,
    reasoning_tokens=8,
    cached_input_tokens=40,
    cache_write_input_tokens=12,
  )
  let v4 = LanguageModelV4Usage::from_usage(usage)
  assert_eq(v4.input_tokens.total, Some(120))
  assert_eq(v4.input_tokens.no_cache, Some(68))
  assert_eq(v4.input_tokens.cache_read, Some(40))
  assert_eq(v4.input_tokens.cache_write, Some(12))
  assert_eq(v4.output_tokens.total, Some(30))
  assert_eq(v4.output_tokens.text, Some(22))
  assert_eq(v4.output_tokens.reasoning, Some(8))
  assert_eq(v4.to_usage(), usage)
}

///|
test "V4 unknown usage does not fabricate zero counters" {
  let usage = LanguageModelV4Usage::unknown()
  assert_eq(usage.input_tokens.total, None)
  assert_eq(usage.input_tokens.no_cache, None)
  assert_eq(usage.input_tokens.cache_read, None)
  assert_eq(usage.input_tokens.cache_write, None)
  assert_eq(usage.output_tokens.total, None)
  assert_eq(usage.output_tokens.text, None)
  assert_eq(usage.output_tokens.reasoning, None)
  assert_eq(usage.raw, None)
}

///|
test "V4 stream conversion preserves lifecycle and diagnostics" {
  let start = LanguageModelV4StreamPart::from_stream_event(StreamStart)
  assert_true(start is V4StreamStart(warnings=values) && values.length() == 0)

  let delta = LanguageModelV4StreamPart::from_stream_event(
    TextDelta(id="text-0", delta="hello"),
  )
  assert_true(
    delta is V4TextDelta(id="text-0", delta="hello", provider_metadata=metadata) &&
    metadata.length() == 0,
  )

  let finish = LanguageModelV4StreamPart::from_stream_event(
    Finish(usage=Usage::zero(), reason=Stop),
  )
  assert_true(
    finish is V4Finish(usage=value, reason~, provider_metadata=metadata) &&
    reason.unified is V4FinishStop &&
    value.input_tokens.total == Some(0) &&
    metadata.length() == 0,
  )

  let error = LanguageModelV4StreamPart::from_stream_event(
    StreamError("broken"),
  )
  assert_true(error is V4Error("broken"))
}

///|
test "V4 prompt is a distinct tagged shape with an explicit wire bridge" {
  let prompt = [
    LanguageModelMessage::system("You are concise"),
    LanguageModelMessage::user_parts([
      LanguageModelContentPart::text("hello"),
      LanguageModelContentPart::file_url(
        url="https://example.com/image.png",
        media_type="image/png",
      ),
    ]),
  ]
  let v4 = LanguageModelV4Prompt::from_language_model_prompt(prompt)
  assert_eq(v4.messages.length(), 2)
  assert_true(v4.messages[0] is V4SystemMessage(content="You are concise", ..))
  assert_true(
    v4.messages[1] is V4UserMessage(content=parts, ..) && parts.length() == 2,
  )

  let round_trip = v4.to_language_model_prompt()
  assert_eq(round_trip.length(), 2)
  assert_true(round_trip[0].role is System)
  assert_true(round_trip[1].role is User)
  assert_eq(round_trip[1].parts.length(), 2)
}

///|
test "V4 prompt bridge preserves text and normalizes wire tool content" {
  let prompt = [
    LanguageModelMessage::user("hello"),
    LanguageModelMessage::user_parts([
      LanguageModelContentPart::image_url("https://example.com/image.png"),
    ]),
    LanguageModelMessage::tool_parts("call-1", [
      LanguageModelContentPart::file_data(
        data="UERG",
        media_type="application/pdf",
        filename="report.pdf",
      ),
    ]),
  ]
  let round_trip = LanguageModelV4Prompt::from_language_model_prompt(prompt).to_language_model_prompt()
  assert_eq(round_trip[0], LanguageModelMessage::user("hello"))
  assert_true(
    round_trip[1].parts[0] is ImageUrl("https://example.com/image.png"),
  )
  assert_true(round_trip[2].role is Tool("call-1"))
  match round_trip[2].parts[0] {
    ToolResultPart(result) => {
      assert_eq(result.tool_call_id, "call-1")
      match result.output {
        LanguageModelToolContent(value~, ..) =>
          assert_true(
            value[0]
            is LanguageModelToolFileData(
              data="UERG",
              media_type="application/pdf",
              filename="report.pdf",
              ..
            ),
          )
        _ => fail("expected normalized multimodal tool output")
      }
    }
    _ => fail("expected a V4 tool-result part")
  }
}

///|
test "V4 call options merge provider values without mutating the source" {
  let original = LanguageModelV4CallOptions::new(
    LanguageModelV4Prompt::new([]),
    provider_options={ "provider": { "keep": true } },
  )
  let derived = original.with_provider_options({ "provider": { "added": 1 } })
  let changed = original.with_reasoning_effort(High)
  assert_true(
    original.provider_options is { "provider": { "keep": true, .. }, .. },
  )
  assert_true(
    derived.provider_options
    is { "provider": { "keep": true, "added": 1, .. }, .. },
  )
  assert_eq(original.reasoning_effort, ProviderDefault)
  assert_eq(changed.reasoning_effort, High)
}
