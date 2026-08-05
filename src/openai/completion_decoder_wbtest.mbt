///|
test "official OpenAI completion turns malformed chunks into stream errors" {
  let decoder = OpenAICompletionStreamDecoder::new(include_raw_chunks=false)
  let _ = decoder.feed_line("data: {not-json")
  let malformed = decoder.feed_line("")
  assert_eq(malformed.done, false)
  assert_true(malformed.events[0] is @provider.StreamError(_))
  let _ = decoder.feed_line("data: [DONE]")
  let terminal = decoder.feed_line("")
  assert_true(
    terminal.events[0] is @provider.Finish(reason=@provider.Error, ..),
  )
  assert_eq(decoder.response().finish_reason, @provider.Error)
}

///|
test "official OpenAI completion emits response metadata once on first valid chunk" {
  let decoder = OpenAICompletionStreamDecoder::new(include_raw_chunks=false)
  let _ = decoder.feed_line(
    "data: {\"id\":\"cmpl-1\",\"model\":\"gpt-test\",\"created\":1700000000,\"choices\":[]}",
  )
  let first = decoder.feed_line("")
  match first.events[0] {
    @provider.ResponseMetadataReady(metadata) => {
      assert_eq(metadata.id, Some("cmpl-1"))
      assert_eq(metadata.model_id, Some("gpt-test"))
      assert_eq(metadata.created_at, Some(1700000000))
    }
    _ => fail("expected response metadata")
  }
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"hello\",\"finish_reason\":\"stop\"}]}",
  )
  let second = decoder.feed_line("")
  assert_true(
    second.events.all(event => !(event is @provider.ResponseMetadataReady(_))),
  )
}

///|
test "official OpenAI completion error chunk does not emit response metadata" {
  let decoder = OpenAICompletionStreamDecoder::new(include_raw_chunks=false)
  let _ = decoder.feed_line(
    "data: {\"id\":\"error-chunk\",\"error\":{\"message\":\"bad\"}}",
  )
  let batch = decoder.feed_line("")
  assert_true(
    batch.events.all(event => !(event is @provider.ResponseMetadataReady(_))),
  )
}
