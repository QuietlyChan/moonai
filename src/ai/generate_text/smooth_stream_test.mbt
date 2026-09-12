///|
test "smooth transformer re-chunks text deltas at word boundaries" {
  let smoother = SmoothTextTransformer::new(chunking=SmoothWord)
  let first = smoother.process(
    @provider.V4TextDelta(id="t1", delta="Hello wor", provider_metadata=Map([])),
  )
  assert_eq(first.length(), 1)
  assert_true(first[0] is @provider.V4TextDelta(id="t1", delta="Hello ", ..))
  let second = smoother.process(
    @provider.V4TextDelta(
      id="t1",
      delta="ld from the stream",
      provider_metadata=Map([]),
    ),
  )
  let chunks : Array[String] = []
  for part in second {
    match part {
      @provider.V4TextDelta(delta~, ..) => chunks.push(delta)
      _ => fail("expected text deltas")
    }
  }
  assert_eq(chunks, ["world ", "from ", "the "])
}

///|
test "smooth transformer flushes buffered text on non-text events" {
  let smoother = SmoothTextTransformer::new(chunking=SmoothWord)
  let _ = smoother.process(
    @provider.V4TextDelta(
      id="t1",
      delta="partial tail",
      provider_metadata=Map([]),
    ),
  )
  let events = smoother.process(
    @provider.V4ToolCallReady(
      @provider.LanguageModelV4ToolCall::from_tool_call(
        @provider.ToolCall::new(
          id="call-1",
          name="lookup",
          arguments="{}",
          provider_metadata=Map([]),
        ),
      ),
    ),
  )
  assert_eq(events.length(), 2)
  assert_true(events[0] is @provider.V4TextDelta(id="t1", delta="tail", ..))
  assert_true(events[1] is @provider.V4ToolCallReady(_))
  // Flushing again produces nothing once drained.
  assert_eq(smoother.flush().length(), 0)
}

///|
test "smooth transformer keeps provider metadata on the flushed tail only" {
  let smoother = SmoothTextTransformer::new(chunking=SmoothLine)
  let metadata : Map[String, Json] = Map([
    ("anthropic", Json::object(Map([("signature", Json::string("sig"))]))),
  ])
  let first = smoother.process(
    @provider.V4TextDelta(
      id="t1",
      delta="line one\nline two starts",
      provider_metadata=metadata,
    ),
  )
  assert_eq(first.length(), 1)
  // The streamed chunk must not leak provider metadata.
  match first[0] {
    @provider.V4TextDelta(delta~, provider_metadata~, ..) => {
      assert_eq(delta, "line one\n")
      assert_eq(provider_metadata.length(), 0)
    }
    _ => fail("expected a text delta")
  }
  let tail = smoother.flush()
  assert_eq(tail.length(), 1)
  match tail[0] {
    @provider.V4TextDelta(delta~, provider_metadata~, ..) => {
      assert_eq(delta, "line two starts")
      assert_true(
        provider_metadata.get("anthropic")
        is Some({ "signature": String("sig"), .. }),
      )
    }
    _ => fail("expected a text delta")
  }
}

///|
test "smooth transformer flushes when the delta id changes" {
  let smoother = SmoothTextTransformer::new(chunking=SmoothWord)
  let _ = smoother.process(
    @provider.V4TextDelta(id="a", delta="first tail", provider_metadata=Map([])),
  )
  let events = smoother.process(
    @provider.V4TextDelta(id="b", delta="second", provider_metadata=Map([])),
  )
  // The id switch flushes the previous buffer before buffering the new one.
  assert_eq(events.length(), 1)
  assert_true(events[0] is @provider.V4TextDelta(id="a", delta="tail", ..))
  let tail = smoother.flush()
  assert_eq(tail.length(), 1)
  assert_true(tail[0] is @provider.V4TextDelta(id="b", delta="second", ..))
}
