///|
test "encode OpenAI-compatible completion requests" {
  let options = @provider.CompletionOptions::new(
    "MoonBit is",
    suffix=".",
    max_output_tokens=20,
    temperature=0.2,
    frequency_penalty=-0.1,
    presence_penalty=0.3,
    seed=42,
    stop_sequences=["END"],
  )
  json_inspect(
    encode_completion_request("completion-model", options, stream=false),
    content={
      "model": "completion-model",
      "prompt": "MoonBit is",
      "suffix": ".",
      "max_tokens": 20,
      "temperature": 0.2,
      "frequency_penalty": -0.1,
      "presence_penalty": 0.3,
      "seed": 42,
      "stop": ["END"],
    },
  )
  json_inspect(
    encode_completion_request("completion-model", options, include_usage=true),
    content={
      "model": "completion-model",
      "prompt": "MoonBit is",
      "stream": true,
      "stream_options": { "include_usage": true },
      "suffix": ".",
      "max_tokens": 20,
      "temperature": 0.2,
      "frequency_penalty": -0.1,
      "presence_penalty": 0.3,
      "seed": 42,
      "stop": ["END"],
    },
  )
}

///|
test "OpenAI-compatible completion omits streaming usage options by default" {
  let options = @provider.CompletionOptions::new("MoonBit")
  assert_false(
    encode_completion_request("completion-model", options)
    .stringify()
    .contains("stream_options"),
  )
}

///|
test "completion provider options use OpenAI wire names" {
  let options = @provider.CompletionOptions::new("MoonBit", provider_options={
    "openai": { "logitBias": { "42": -2.0 }, "echo": true },
  })
  json_inspect(
    encode_completion_request(
      "gpt-3.5-turbo-instruct",
      options,
      stream=false,
      provider_name="openai.completion",
    ),
    content={
      "model": "gpt-3.5-turbo-instruct",
      "prompt": "MoonBit",
      "logit_bias": { "42": -2.0 },
      "echo": true,
    },
  )
}

///|
test "decode OpenAI-compatible completion response" {
  let response = decode_completion_response({
    "choices": [{ "text": " fast.", "finish_reason": "stop" }],
    "usage": { "prompt_tokens": 2, "completion_tokens": 2, "total_tokens": 4 },
  })
  assert_eq(response.text, " fast.")
  assert_eq(response.finish_reason, @provider.Stop)
  assert_eq(response.usage.total_tokens, 4)
}

///|
test "decode OpenAI-compatible completion stream" {
  let decoder = OpenAICompatibleCompletionStreamDecoder::new()
  let first = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"Moon\",\"finish_reason\":null}]}",
  )
  assert_eq(first.events.length(), 0)
  let text = decoder.feed_line("")
  assert_eq(text.events.length(), 3)
  assert_true(text.events[0] is @provider.ResponseMetadataReady(_))
  assert_true(text.events[1] is @provider.TextStart(_))
  assert_true(text.events[2] is @provider.TextDelta(..))
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
  assert_eq(
    decoder.response(),
    @provider.CompletionResponse::new(
      "MoonBit",
      {
        input_tokens: 1,
        output_tokens: 2,
        total_tokens: 3,
        reasoning_tokens: 0,
        cached_input_tokens: 0,
        cache_write_input_tokens: 0,
      },
      @provider.Stop,
    ),
  )
}

///|
test "compatible completion emits response metadata once on first valid chunk" {
  let decoder = OpenAICompatibleCompletionStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"id\":\"cmpl-1\",\"model\":\"local-test\",\"created\":1700000000,\"choices\":[]}",
  )
  let first = decoder.feed_line("")
  match first.events[0] {
    @provider.ResponseMetadataReady(metadata) => {
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
    second.events.all(event => !(event is @provider.ResponseMetadataReady(_))),
  )
}

///|
test "compatible completion error chunk does not emit response metadata" {
  let decoder = OpenAICompatibleCompletionStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"id\":\"error-chunk\",\"error\":{\"message\":\"bad\"}}",
  )
  let batch = decoder.feed_line("")
  assert_true(
    batch.events.all(event => !(event is @provider.ResponseMetadataReady(_))),
  )
}

///|
test "completion EOF without a finish reason is not a successful stream" {
  let decoder = OpenAICompatibleCompletionStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"partial\",\"finish_reason\":null}]}\n",
  )
  let buffered = decoder.flush_buffered()
  assert_eq(buffered.done, false)
  assert_eq(decoder.response().finish_reason, @provider.Unknown(""))
}

///|
test "completion EOF after a finish reason emits one terminal event" {
  let decoder = OpenAICompatibleCompletionStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"complete\",\"finish_reason\":\"stop\"}]}\n",
  )
  let buffered = decoder.flush_buffered()
  assert_eq(buffered.done, true)
  let mut finishes = 0
  for event in buffered.events {
    if event is @provider.Finish(..) {
      finishes = finishes + 1
    }
  }
  assert_eq(finishes, 1)
  assert_eq(decoder.response().finish_reason, @provider.Stop)
}

///|
test "completion include_raw_chunks exposes parsed provider chunks" {
  let decoder = OpenAICompatibleCompletionStreamDecoder::new(
    include_raw_chunks=true,
  )
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"raw\",\"finish_reason\":null}]}",
  )
  let chunk = decoder.feed_line("")
  assert_true(chunk.events[0] is @provider.Raw(_))
  assert_true(chunk.events[1] is @provider.ResponseMetadataReady(_))
  assert_true(chunk.events[2] is @provider.TextStart(_))
  assert_true(chunk.events[3] is @provider.TextDelta(..))
}

///|
test "completion non-streaming errors and empty choices are explicit" {
  try
    decode_completion_response({ "error": { "message": "bad prompt" } })
  catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("bad prompt"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected completion provider error")
  }
  try decode_completion_response({ "choices": [] }) catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_true(message.contains("no choices"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected empty completion choices")
  }
}

///|
test "compatible completion turns malformed chunks into stream errors" {
  let decoder = OpenAICompatibleCompletionStreamDecoder::new()
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
