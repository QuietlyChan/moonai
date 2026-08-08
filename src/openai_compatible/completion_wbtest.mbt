///|
fn compatible_test_completion_decoder(
  include_raw_chunks? : Bool = false,
) -> OpenAICompatibleCompletionStreamDecoder {
  OpenAICompatibleCompletionStreamDecoder::new(
    include_raw_chunks,
    "openai-compatible.completion",
    default_openai_compatible_error_structure(),
  )
}

///|
fn decode_compatible_test_completion(
  json : Json,
) -> @provider.CompletionResponse raise {
  let decoded = decode_completion_response(
    json,
    default_openai_compatible_error_structure(),
  )
  let text = StringBuilder::new()
  for part in decoded.content {
    match part {
      @provider.V4TextOutput(value) => text.write_string(value.text)
      _ => ()
    }
  }
  @provider.CompletionResponse::new(
    text.to_string(),
    decoded.usage.to_usage(),
    match decoded.finish_reason {
      { unified: @provider.V4FinishOther, raw: None } => @provider.Unknown("")
      reason => reason.to_finish_reason()
    },
  )
}

///|
test "OpenAI-compatible completion usage is unknown when omitted" {
  assert_eq(
    convert_openai_compatible_completion_usage(None),
    @provider.LanguageModelV4Usage::unknown(),
  )
  assert_eq(
    convert_openai_compatible_completion_usage(Some(Json::null())),
    @provider.LanguageModelV4Usage::unknown(),
  )
}

///|
test "decode OpenAI-compatible completion response" {
  let response = decode_compatible_test_completion({
    "choices": [{ "text": " fast.", "finish_reason": "stop" }],
    "usage": { "prompt_tokens": 2, "completion_tokens": 2, "total_tokens": 4 },
  })
  assert_eq(response.text, " fast.")
  assert_eq(response.finish_reason, @provider.Stop)
  assert_eq(response.usage.total_tokens, 4)
}

///|
test "compatible completion keeps a missing finish reason unknown" {
  let response = decode_compatible_test_completion({
    "choices": [{ "text": "partial" }],
  })
  assert_eq(response.finish_reason, @provider.Unknown(""))

  let decoder = compatible_test_completion_decoder()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"partial\",\"finish_reason\":null}]}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line("data: [DONE]")
  let terminal = decoder.feed_line("")
  assert_true(
    terminal.events.any(event => {
      event
      is @provider.V4Finish(
        reason={ unified: @provider.V4FinishOther, raw: None },
        ..
      )
    }),
  )
  assert_true(decoder.v4_finish_reason().unified is @provider.V4FinishOther)
  assert_eq(decoder.v4_finish_reason().raw, None)
}

///|
test "decode OpenAI-compatible completion stream" {
  let decoder = compatible_test_completion_decoder()
  let first = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"Moon\",\"finish_reason\":null}]}",
  )
  assert_eq(first.events.length(), 0)
  let text = decoder.feed_line("")
  assert_eq(text.events.length(), 3)
  assert_true(text.events[0] is @provider.V4ResponseMetadataReady(_))
  assert_true(text.events[1] is @provider.V4TextStart(..))
  assert_true(text.events[2] is @provider.V4TextDelta(..))
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"Bit\",\"finish_reason\":\"stop\"}]}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line("data: [DONE]")
  let terminal = decoder.feed_line("")
  assert_eq(terminal.done, true)
  assert_eq(decoder.text.to_string(), "MoonBit")
  assert_eq(decoder.v4_usage().to_usage(), {
    input_tokens: 1,
    output_tokens: 2,
    total_tokens: 3,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  })
  assert_true(decoder.v4_finish_reason().unified is @provider.V4FinishStop)
}

///|
test "compatible completion starts text on the first successful chunk" {
  let decoder = compatible_test_completion_decoder()
  let _ = decoder.feed_line(
    "data: {\"id\":\"cmpl-1\",\"choices\":[],\"usage\":null}",
  )
  let first = decoder.feed_line("")
  assert_eq(first.events.length(), 2)
  assert_true(first.events[0] is @provider.V4ResponseMetadataReady(_))
  assert_true(first.events[1] is @provider.V4TextStart(id="0", ..))

  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"\",\"finish_reason\":\"stop\"}]}",
  )
  let empty_delta = decoder.feed_line("")
  assert_true(
    empty_delta.events.any(event => {
      event is @provider.V4TextDelta(id="0", delta="", ..)
    }),
  )
  let _ = decoder.feed_line("data: [DONE]")
  let terminal = decoder.feed_line("")
  assert_true(
    terminal.events.any(event => event is @provider.V4TextEnd(id="0", ..)),
  )
}

///|
test "compatible completion emits response metadata once on first valid chunk" {
  let decoder = compatible_test_completion_decoder()
  let _ = decoder.feed_line(
    "data: {\"id\":\"cmpl-1\",\"model\":\"local-test\",\"created\":1700000000,\"choices\":[]}",
  )
  let first = decoder.feed_line("")
  match first.events[0] {
    @provider.V4ResponseMetadataReady(metadata) => {
      assert_eq(metadata.id, Some("cmpl-1"))
      assert_eq(metadata.model_id, Some("local-test"))
      assert_eq(metadata.created_at, Some(1700000000))
    }
    _ => fail("expected response metadata")
  }
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"hello\",\"finish_reason\":\"stop\"}]}",
  )
  let second = decoder.feed_line("")
  assert_true(
    second.events.all(event => !(event is @provider.V4ResponseMetadataReady(_))),
  )
}

///|
test "compatible completion error chunk does not emit response metadata" {
  let decoder = compatible_test_completion_decoder()
  let _ = decoder.feed_line(
    "data: {\"id\":\"error-chunk\",\"error\":{\"message\":\"bad\"}}",
  )
  let batch = decoder.feed_line("")
  assert_true(
    batch.events.all(event => !(event is @provider.V4ResponseMetadataReady(_))),
  )
}

///|
test "completion normal EOF finalizes with an unknown finish reason" {
  let decoder = compatible_test_completion_decoder()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"partial\",\"finish_reason\":null}]}\n",
  )
  let buffered = decoder.flush_buffered()
  assert_eq(buffered.done, false)
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
  assert_true(decoder.v4_finish_reason().unified is @provider.V4FinishOther)
  assert_eq(decoder.v4_finish_reason().raw, None)
}

///|
test "completion EOF after a finish reason emits one terminal event" {
  let decoder = compatible_test_completion_decoder()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"complete\",\"finish_reason\":\"stop\"}]}\n",
  )
  let buffered = decoder.flush_buffered()
  assert_eq(buffered.done, false)
  let terminal = decoder.finish_stream()
  assert_true(terminal.done)
  let mut finishes = 0
  for event in terminal.events {
    if event is @provider.V4Finish(..) {
      finishes = finishes + 1
    }
  }
  assert_eq(finishes, 1)
  assert_true(decoder.v4_finish_reason().unified is @provider.V4FinishStop)
}

///|
test "completion include_raw_chunks exposes parsed provider chunks" {
  let decoder = compatible_test_completion_decoder(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"raw\",\"finish_reason\":null}]}",
  )
  let chunk = decoder.feed_line("")
  assert_true(chunk.events[0] is @provider.V4Raw(_))
  assert_true(chunk.events[1] is @provider.V4ResponseMetadataReady(_))
  assert_true(chunk.events[2] is @provider.V4TextStart(..))
  assert_true(chunk.events[3] is @provider.V4TextDelta(..))
}

///|
test "completion non-streaming errors and empty choices are explicit" {
  try
    decode_compatible_test_completion({ "error": { "message": "bad prompt" } })
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("bad prompt"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected completion provider error")
  }
  try decode_compatible_test_completion({ "choices": [] }) catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("no choices"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected empty completion choices")
  }
}

///|
test "compatible completion validates structured successful responses" {
  try
    decode_compatible_test_completion({
      "id": 42,
      "choices": [{ "text": "invalid metadata", "finish_reason": "stop" }],
    })
  catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("id and model"))
      assert_true(data is { "id": 42, .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected completion response validation error")
  }

  let decoder = compatible_test_completion_decoder(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"id\":42,\"choices\":[{\"text\":\"invalid\",\"finish_reason\":null}]}",
  )
  let batch = decoder.feed_line("")
  assert_true(batch.events[0] is @provider.V4Raw({ "id": 42, .. }))
  assert_true(batch.events[1] is @provider.V4Error(_))
  assert_true(decoder.v4_finish_reason().unified is @provider.V4FinishError)
}

///|
test "compatible completion turns malformed chunks into stream errors" {
  let decoder = compatible_test_completion_decoder(include_raw_chunks=true)
  let _ = decoder.feed_line("data: {not-json")
  let malformed = decoder.feed_line("")
  assert_eq(malformed.done, false)
  assert_true(malformed.events[0] is @provider.V4Raw(String("{not-json")))
  assert_true(malformed.events[1] is @provider.V4Error(_))
  let _ = decoder.feed_line("data: [DONE]")
  let terminal = decoder.feed_line("")
  assert_true(
    terminal.events[0]
    is @provider.V4Finish(reason={ unified: @provider.V4FinishError, .. }, ..),
  )
  assert_true(decoder.v4_finish_reason().unified is @provider.V4FinishError)
}

///|
test "compatible completion retains structured provider errors" {
  let decoder = compatible_test_completion_decoder(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"error\":{\"message\":\"quota exceeded\",\"code\":\"quota\"}}",
  )
  let error_batch = decoder.feed_line("")
  assert_eq(error_batch.done, false)
  assert_true(error_batch.events[0] is @provider.V4Raw(_))
  match error_batch.events[1] {
    @provider.V4Error(error) => {
      assert_eq(error.message, "quota exceeded")
      assert_true(error.data is Some({ "code": "quota", .. }))
    }
    _ => fail("expected a structured compatible completion error")
  }
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
