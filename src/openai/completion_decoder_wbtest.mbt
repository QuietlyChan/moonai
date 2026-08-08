///|
test "official OpenAI completion turns malformed chunks into stream errors" {
  let decoder = OpenAICompletionStreamDecoder::new(include_raw_chunks=true)
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
test "official OpenAI completion normal EOF finalizes a partial response" {
  let decoder = OpenAICompletionStreamDecoder::new(include_raw_chunks=false)
  let _ = decoder.feed_line(
    "data: {\"id\":\"cmpl-partial\",\"choices\":[{\"text\":\"partial\",\"finish_reason\":null}]}",
  )
  let chunk = decoder.feed_line("")
  assert_true(
    chunk.events.any(event => {
      event is @provider.V4TextDelta(id="0", delta="partial", ..)
    }),
  )
  assert_false(decoder.flush_buffered().done)
  let terminal = decoder.finish_stream()
  assert_true(terminal.done)
  assert_true(terminal.events[0] is @provider.V4TextEnd(id="0", ..))
  assert_true(
    terminal.events[1]
    is @provider.V4Finish(
      reason={ unified: @provider.V4FinishOther, raw: None },
      ..
    ),
  )
}

///|
test "official OpenAI completion emits response metadata once on first valid chunk" {
  let decoder = OpenAICompletionStreamDecoder::new(include_raw_chunks=false)
  let _ = decoder.feed_line(
    "data: {\"id\":\"cmpl-1\",\"model\":\"gpt-test\",\"created\":1700000000,\"choices\":[]}",
  )
  let first = decoder.feed_line("")
  match first.events[0] {
    @provider.V4ResponseMetadataReady(metadata) => {
      assert_eq(metadata.id, Some("cmpl-1"))
      assert_eq(metadata.model_id, Some("gpt-test"))
      assert_eq(metadata.created_at, Some(1700000000))
    }
    _ => fail("expected response metadata")
  }
  assert_true(first.events[1] is @provider.V4TextStart(id="0", ..))
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"hello\",\"finish_reason\":\"stop\"}]}",
  )
  let second = decoder.feed_line("")
  assert_true(
    second.events[0] is @provider.V4TextDelta(id="0", delta="hello", ..),
  )
  assert_true(
    second.events.all(event => !(event is @provider.V4ResponseMetadataReady(_))),
  )
}

///|
test "official OpenAI completion raises provider errors before output" {
  let decoder = OpenAICompletionStreamDecoder::new(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"id\":\"error-chunk\",\"error\":{\"message\":\"bad\",\"code\":\"insufficient_quota\"}}",
  )
  try decoder.feed_line("") catch {
    @provider_utils.SseProviderError(message~, status_code~, ..) => {
      assert_eq(message, "bad")
      assert_eq(status_code, 429)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected an early completion provider error")
  }
  assert_true(decoder.response_metadata_snapshot() is None)
}

///|
test "official OpenAI completion keeps provider errors after output in stream" {
  let decoder = OpenAICompletionStreamDecoder::new(include_raw_chunks=true)
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"hello\",\"finish_reason\":null}]}",
  )
  let output = decoder.feed_line("")
  assert_true(output.events.any(event => event is @provider.V4TextDelta(..)))
  decoder.mark_stream_started()
  let _ = decoder.feed_line(
    "data: {\"error\":{\"message\":\"bad\",\"type\":\"server_error\"}}",
  )
  let batch = decoder.feed_line("")
  assert_true(batch.events[0] is @provider.V4Raw(_))
  assert_true(batch.events[1] is @provider.V4Error({ message: "bad", .. }))
}

///|
test "official OpenAI completion retains V4 stream usage and finish reason" {
  let decoder = OpenAICompletionStreamDecoder::new(include_raw_chunks=false)
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"done\",\"finish_reason\":\"length\"}],\"usage\":{\"completion_tokens\":4}}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line("data: [DONE]")
  let terminal = decoder.feed_line("")
  assert_true(terminal.events[0] is @provider.V4TextEnd(id="0", ..))
  let usage = decoder.v4_usage()
  assert_eq(usage.input_tokens.total, None)
  assert_eq(usage.output_tokens.total, Some(4))
  assert_eq(usage.output_tokens.reasoning, None)
  assert_eq(decoder.v4_finish_reason().unified, @provider.V4FinishLength)
  assert_eq(decoder.v4_finish_reason().raw, Some("length"))
}

///|
test "official OpenAI completion keeps the latest streamed logprobs object" {
  let decoder = OpenAICompletionStreamDecoder::new(include_raw_chunks=false)
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"first\",\"logprobs\":{\"tokens\":[\"first\"]},\"finish_reason\":null}]}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"second\",\"logprobs\":{\"tokens\":[\"second\"]},\"finish_reason\":\"stop\"}]}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line("data: [DONE]")
  let terminal = decoder.feed_line("")
  match terminal.events[1] {
    @provider.V4Finish(provider_metadata~, ..) =>
      json_inspect(provider_metadata["openai"], content={
        "logprobs": { "tokens": ["second"] },
      })
    _ => fail("expected terminal completion metadata")
  }
}
