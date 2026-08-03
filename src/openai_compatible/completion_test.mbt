///|
test "encode OpenAI-compatible completion requests" {
  let options = @moonai.CompletionOptions::new(
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
  json_inspect(encode_completion_request("completion-model", options), content={
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
  })
}

///|
test "decode OpenAI-compatible completion response" {
  let response = decode_completion_response({
    "choices": [{ "text": " fast.", "finish_reason": "stop" }],
    "usage": { "prompt_tokens": 2, "completion_tokens": 2, "total_tokens": 4 },
  })
  assert_eq(response.text, " fast.")
  assert_eq(response.finish_reason, @moonai.Stop)
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
  assert_eq(text.events.length(), 2)
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
  assert_eq(decoder.response(), {
    text: "MoonBit",
    usage: {
      input_tokens: 1,
      output_tokens: 2,
      total_tokens: 3,
      reasoning_tokens: 0,
      cached_input_tokens: 0,
    },
    finish_reason: @moonai.Stop,
  })
}

///|
test "completion EOF without a finish reason is not a successful stream" {
  let decoder = OpenAICompatibleCompletionStreamDecoder::new()
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"text\":\"partial\",\"finish_reason\":null}]}\n",
  )
  let buffered = decoder.flush_buffered()
  assert_eq(buffered.done, false)
  assert_eq(decoder.response().finish_reason, @moonai.Unknown(""))
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
    if event is @moonai.Finish(..) {
      finishes = finishes + 1
    }
  }
  assert_eq(finishes, 1)
  assert_eq(decoder.response().finish_reason, @moonai.Stop)
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
  assert_true(chunk.events[0] is @moonai.Raw(_))
  assert_true(chunk.events[1] is @moonai.TextStart(_))
  assert_true(chunk.events[2] is @moonai.TextDelta(..))
}

///|
test "completion non-streaming errors and empty choices are explicit" {
  try
    decode_completion_response({ "error": { "message": "bad prompt" } })
  catch {
    Failure::Failure(message) => assert_true(message.contains("bad prompt"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected completion provider error")
  }
  try decode_completion_response({ "choices": [] }) catch {
    Failure::Failure(message) => assert_true(message.contains("no choices"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected empty completion choices")
  }
}
