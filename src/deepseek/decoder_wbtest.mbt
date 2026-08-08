///|
test "DeepSeek stream errors retain the provider payload" {
  let decoder = DeepSeekStreamDecoder::new(
    include_raw_chunks=false,
    provider_name="deepseek.chat",
    id_generator=@provider_utils.generate_id,
  )
  let _ = decoder.feed_line(
    "data: {\"error\":{\"message\":\"busy\",\"type\":\"server_error\",\"code\":\"overloaded\"}}",
  )
  let error_batch = decoder.feed_line("")
  assert_eq(error_batch.done, false)
  match error_batch.events[0] {
    @provider.V4Error(error) => {
      assert_eq(error.message, "busy")
      assert_true(
        error.data is Some({ "type": "server_error", "code": "overloaded", .. }),
      )
    }
    _ => fail("expected a structured DeepSeek stream error")
  }
  assert_false(error_batch.events.any(event => event is @provider.V4Finish(..)))
  let terminal = decoder.finish_stream()
  assert_eq(terminal.done, true)
  assert_true(
    terminal.events[0]
    is @provider.V4Finish(
      reason={ unified: @provider.V4FinishError, raw: None },
      ..
    ),
  )
}

///|
test "DeepSeek malformed chunks become ordered raw and error events" {
  let decoder = DeepSeekStreamDecoder::new(
    include_raw_chunks=true,
    provider_name="deepseek.chat",
    id_generator=@provider_utils.generate_id,
  )
  let _ = decoder.feed_line("data: {not-json")
  let malformed = decoder.feed_line("")
  assert_eq(malformed.done, false)
  assert_true(malformed.events[0] is @provider.V4Raw("{not-json"))
  match malformed.events[1] {
    @provider.V4Error(error) => {
      assert_true(error.message.contains("DeepSeek stream decode error"))
      assert_eq(error.data, Some("{not-json"))
    }
    _ => fail("expected a structured parse error")
  }
  let terminal = decoder.finish_stream()
  assert_eq(terminal.done, true)
  assert_true(
    terminal.events[0]
    is @provider.V4Finish(reason={ unified: @provider.V4FinishError, .. }, ..),
  )
}

///|
test "DeepSeek stream lifecycle matches AI SDK transition order" {
  let decoder = DeepSeekStreamDecoder::new(
    include_raw_chunks=false,
    provider_name="deepseek.chat",
    id_generator=() => "generated-call",
  )
  let _ = decoder.feed_line(
    "data: {\"id\":\"stream-1\",\"choices\":[{\"delta\":{\"reasoning_content\":\"plan\"},\"finish_reason\":null}]}",
  )
  let reasoning = decoder.feed_line("")
  assert_true(
    reasoning.events[1] is @provider.V4ReasoningStart(id="reasoning-0", ..),
  )
  assert_true(
    reasoning.events[2]
    is @provider.V4ReasoningDelta(id="reasoning-0", delta="plan", ..),
  )

  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"content\":\"answer\"},\"finish_reason\":null}]}",
  )
  let text = decoder.feed_line("")
  assert_eq(text.events.length(), 3)
  assert_true(text.events[0] is @provider.V4TextStart(id="txt-0", ..))
  assert_true(text.events[1] is @provider.V4ReasoningEnd(id="reasoning-0", ..))
  assert_true(
    text.events[2] is @provider.V4TextDelta(id="txt-0", delta="answer", ..),
  )

  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call-1\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{}\"}}]},\"finish_reason\":\"tool_calls\"}]}",
  )
  let tool = decoder.feed_line("")
  assert_true(
    !tool.events.any(event => event is @provider.V4TextEnd(id="txt-0", ..)),
  )
  assert_true(tool.events.any(event => event is @provider.V4ToolInputStart(..)))

  let _ = decoder.feed_line("data: [DONE]")
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  assert_true(terminal.events[0] is @provider.V4TextEnd(id="txt-0", ..))
  assert_true(
    terminal.events.any(event => event is @provider.V4ToolCallReady(_)),
  )
  assert_true(
    terminal.events.any(event => {
      event
      is @provider.V4Finish(
        reason={ unified: @provider.V4FinishToolCalls, raw: Some("tool_calls") },
        ..
      )
    }),
  )
}

///|
test "DeepSeek schema-invalid chunks become ordered raw and error events" {
  let decoder = DeepSeekStreamDecoder::new(
    include_raw_chunks=true,
    provider_name="deepseek.chat",
    id_generator=@provider_utils.generate_id,
  )
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":\"zero\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{}\"}}]},\"finish_reason\":null}]}",
  )
  let invalid = decoder.feed_line("")
  assert_false(invalid.done)
  assert_true(invalid.events[0] is @provider.V4Raw(_))
  match invalid.events[1] {
    @provider.V4Error(error) => {
      assert_true(error.message.contains("numeric index"))
      assert_true(error.data is Some({ "choices": Array(_), .. }))
    }
    _ => fail("expected a DeepSeek schema validation error")
  }
  let terminal = decoder.finish_stream()
  assert_true(terminal.done)
  assert_true(
    terminal.events[0]
    is @provider.V4Finish(reason={ unified: @provider.V4FinishError, .. }, ..),
  )
}

///|
test "DeepSeek does not infer a finish reason omitted by the provider" {
  let decoder = DeepSeekStreamDecoder::new(
    include_raw_chunks=false,
    provider_name="deepseek.chat",
    id_generator=@provider_utils.generate_id,
  )
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"content\":\"answer\"},\"finish_reason\":null}]}",
  )
  let _ = decoder.feed_line("")
  assert_false(decoder.flush_buffered().done)
  let terminal = decoder.finish_stream()
  assert_true(terminal.done)
  assert_true(
    terminal.events.any(event => {
      event
      is @provider.V4Finish(
        reason={ unified: @provider.V4FinishOther, raw: None },
        ..
      )
    }),
  )
}

///|
test "DeepSeek closes a stream at EOF after a provider finish reason" {
  let decoder = DeepSeekStreamDecoder::new(
    include_raw_chunks=false,
    provider_name="deepseek.chat",
    id_generator=@provider_utils.generate_id,
  )
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"delta\":{\"content\":\"answer\"},\"finish_reason\":\"stop\"}]}",
  )
  let chunk = decoder.feed_line("")
  assert_false(chunk.done)
  assert_false(decoder.flush_buffered().done)
  let terminal = decoder.finish_stream()
  assert_true(terminal.done)
  assert_true(
    terminal.events.any(event => {
      event
      is @provider.V4Finish(
        reason={ unified: @provider.V4FinishStop, raw: Some("stop") },
        ..
      )
    }),
  )
}
