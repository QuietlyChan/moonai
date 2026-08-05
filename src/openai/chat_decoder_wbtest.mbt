///|
fn openai_chat_test_id_generator() -> @provider_utils.IdGenerator {
  let mut index = 0
  () => {
    let id = if index == 0 { "tool-call-0" } else { "source-0" }
    index = index + 1
    id
  }
}

///|
test "official OpenAI Chat decodes citations and detailed usage" {
  let response = decode_openai_chat_response(
    {
      "id": "chatcmpl_1",
      "model": "gpt-4o",
      "created": 1700000000,
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "content": "A cited answer.",
            "tool_calls": [
              {
                "type": "function",
                "function": {
                  "name": "lookup",
                  "arguments": "{\"query\":\"MoonBit\"}",
                },
              },
            ],
            "annotations": [
              {
                "type": "url_citation",
                "url_citation": {
                  "start_index": 2,
                  "end_index": 7,
                  "url": "https://www.moonbitlang.com/",
                  "title": "MoonBit",
                },
              },
            ],
          },
          "finish_reason": "function_call",
          "logprobs": { "content": [{ "token": "answer", "logprob": -0.1 }] },
        },
      ],
      "usage": {
        "prompt_tokens": 12,
        "completion_tokens": 7,
        "prompt_tokens_details": { "cached_tokens": 3, "cache_write_tokens": 2 },
        "completion_tokens_details": {
          "reasoning_tokens": 1,
          "accepted_prediction_tokens": 4,
          "rejected_prediction_tokens": 2,
        },
      },
    },
    "openai.chat",
    openai_chat_test_id_generator(),
  )
  assert_eq(response.text, "A cited answer.")
  assert_eq(response.tool_calls, [
    @provider.ToolCall::new(
      id="tool-call-0",
      name="lookup",
      arguments="{\"query\":\"MoonBit\"}",
    ),
  ])
  assert_eq(response.finish_reason, @provider.ToolCalls)
  assert_eq(response.usage, {
    input_tokens: 12,
    output_tokens: 7,
    total_tokens: 19,
    reasoning_tokens: 1,
    cached_input_tokens: 3,
    cache_write_input_tokens: 2,
  })
  assert_eq(response.response.unwrap().id, Some("chatcmpl_1"))
  assert_eq(response.response.unwrap().model_id, Some("gpt-4o"))
  assert_eq(response.content.length(), 3)
  match response.content[2] {
    @provider.GeneratedSourceOutput(
      @provider.GeneratedUrlSource(id~, url~, title~, ..)
    ) => {
      assert_eq(id, "source-0")
      assert_eq(url, "https://www.moonbitlang.com/")
      assert_eq(title, Some("MoonBit"))
    }
    _ => fail("expected an OpenAI URL citation")
  }
  json_inspect(response.provider_metadata["openai"], content={
    "acceptedPredictionTokens": 4,
    "rejectedPredictionTokens": 2,
    "logprobs": [{ "token": "answer", "logprob": -0.1 }],
  })
}

///|
test "official OpenAI Chat stream owns metadata citations tools and usage" {
  let decoder = OpenAIChatStreamDecoder::new(
    include_raw_chunks=true,
    provider_name="openai.chat",
    id_generator=() => "generated-id",
  )
  let events : Array[@provider.StreamEvent] = []
  let feed = line => {
    let batch = decoder.feed_line(line)
    for event in batch.events {
      events.push(event)
    }
    batch
  }
  let _ = feed(
    "data: {\"created\":0,\"choices\":[],\"prompt_filter_results\":[]}",
  )
  let _ = feed("")
  let _ = feed(
    "data: {\"id\":\"chatcmpl_stream\",\"model\":\"gpt-4o\",\"created\":1700000001,\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Moon\",\"annotations\":[{\"type\":\"url_citation\",\"url_citation\":{\"start_index\":0,\"end_index\":4,\"url\":\"https://moonbitlang.com\",\"title\":\"MoonBit\"}}]},\"finish_reason\":null,\"logprobs\":{\"content\":[{\"token\":\"Moon\",\"logprob\":-0.2}]}}]}",
  )
  let _ = feed("")
  let _ = feed(
    "data: {\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{\\\"q\\\":\\\"MoonBit\\\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}",
  )
  let _ = feed("")
  let _ = feed(
    "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15,\"prompt_tokens_details\":{\"cached_tokens\":2,\"cache_write_tokens\":1},\"completion_tokens_details\":{\"reasoning_tokens\":1,\"accepted_prediction_tokens\":3,\"rejected_prediction_tokens\":1}}}",
  )
  let _ = feed("")
  let _ = feed("data: [DONE]")
  let terminal = feed("")
  assert_true(terminal.done)
  let mut raw_count = 0
  let mut metadata_count = 0
  let mut source_count = 0
  let mut tool_count = 0
  for event in events {
    match event {
      @provider.Raw(_) => raw_count = raw_count + 1
      @provider.ResponseMetadataReady(metadata) => {
        metadata_count = metadata_count + 1
        assert_eq(metadata.id, Some("chatcmpl_stream"))
        assert_eq(metadata.created_at, Some(1700000001))
      }
      @provider.SourceReady(
        @provider.GeneratedUrlSource(url="https://moonbitlang.com", ..)
      ) => source_count = source_count + 1
      @provider.ToolCallReady(call) => {
        tool_count = tool_count + 1
        assert_eq(call.id, "call_1")
      }
      _ => ()
    }
  }
  assert_eq(raw_count, 4)
  assert_eq(metadata_count, 1)
  assert_eq(source_count, 1)
  assert_eq(tool_count, 1)
  let response = decoder.response()
  assert_eq(response.text, "Moon")
  assert_eq(response.finish_reason, @provider.ToolCalls)
  assert_eq(response.usage, {
    input_tokens: 10,
    output_tokens: 5,
    total_tokens: 15,
    reasoning_tokens: 1,
    cached_input_tokens: 2,
    cache_write_input_tokens: 1,
  })
  assert_eq(response.content.length(), 3)
  assert_eq(response.response.unwrap().id, Some("chatcmpl_stream"))
  json_inspect(response.provider_metadata["openai"], content={
    "logprobs": [{ "token": "Moon", "logprob": -0.2 }],
    "acceptedPredictionTokens": 3,
    "rejectedPredictionTokens": 1,
  })
}

///|
test "official OpenAI Chat stream errors do not finalize partial tools" {
  let decoder = OpenAIChatStreamDecoder::new(
    include_raw_chunks=false,
    provider_name="openai.chat",
    id_generator=() => "generated-id",
  )
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{\"}}]},\"finish_reason\":null}]}",
  )
  let _ = decoder.feed_line("")
  let _ = decoder.feed_line(
    "data: {\"error\":{\"message\":\"stream failed\",\"type\":\"server_error\"}}",
  )
  let terminal = decoder.feed_line("")
  assert_true(terminal.done)
  assert_true(
    terminal.events.any(event => event is @provider.StreamError("stream failed")),
  )
  assert_false(
    terminal.events.any(event => event is @provider.ToolCallReady(_)),
  )
  assert_eq(decoder.response().finish_reason, @provider.Error)
  assert_eq(decoder.response().tool_calls.length(), 0)
}

///|
test "official OpenAI Chat turns malformed chunks into stream errors" {
  let decoder = OpenAIChatStreamDecoder::new(
    include_raw_chunks=false,
    provider_name="openai.chat",
    id_generator=() => "generated-id",
  )
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
