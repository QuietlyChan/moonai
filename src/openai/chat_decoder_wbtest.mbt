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
fn decode_openai_chat_test_response(
  json : Json,
  provider_name : String,
  id_generator : @provider_utils.IdGenerator,
) -> @provider.ChatResponse raise {
  let decoded = decode_openai_chat_response(json, provider_name, id_generator)
  @provider.ChatResponse::from_content(
    @provider.LanguageModelV4Content::to_generated_content_array(
      decoded.content,
    ),
    decoded.usage.to_usage(),
    match decoded.finish_reason {
      { unified: @provider.V4FinishOther, raw: None } => @provider.Unknown("")
      reason => reason.to_finish_reason()
    },
  ).with_diagnostics(None, decoded.response, decoded.provider_metadata, [])
}

///|
test "official OpenAI Chat normal EOF finalizes a partial response" {
  let decoder = OpenAIChatStreamDecoder::new(
    include_raw_chunks=false,
    provider_name="openai.chat",
    id_generator=() => "generated-id",
  )
  let _ = decoder.feed_line(
    "data: {\"id\":\"chatcmpl-partial\",\"model\":\"gpt-test\",\"choices\":[{\"delta\":{\"content\":\"partial\"},\"finish_reason\":null}]}",
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
  assert_true(decoder.finish_stream().events.is_empty())
}

///|
test "OpenAI Chat keeps provider metadata in the OpenAI namespace" {
  let response = decode_openai_chat_test_response(
    {
      "id": "chatcmpl-provider-key",
      "model": "gpt-4o",
      "created": 1700000000,
      "choices": [
        {
          "index": 0,
          "message": { "role": "assistant", "content": "hello" },
          "finish_reason": "stop",
        },
      ],
      "usage": { "prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2 },
    },
    "azure.chat",
    () => "generated-id",
  )
  json_inspect(response.provider_metadata, content={
    "openai": Json::empty_object(),
  })
}

///|
test "official OpenAI Chat decodes citations and detailed usage" {
  let response = decode_openai_chat_test_response(
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
  let events : Array[@provider.LanguageModelV4StreamPart] = []
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
  let mut text_start_count = 0
  let mut text_delta_count = 0
  let mut text_end_count = 0
  for event in events {
    match event {
      @provider.V4Raw(_) => raw_count = raw_count + 1
      @provider.V4ResponseMetadataReady(metadata) => {
        metadata_count = metadata_count + 1
        assert_eq(metadata.id, Some("chatcmpl_stream"))
        assert_eq(metadata.created_at, Some(1700000001))
      }
      @provider.V4SourceReady(
        @provider.V4UrlSource(url="https://moonbitlang.com", ..)
      ) => source_count = source_count + 1
      @provider.V4ToolCallReady(call) => {
        tool_count = tool_count + 1
        assert_eq(call.tool_call_id, "call_1")
      }
      @provider.V4TextStart(id="0", ..) =>
        text_start_count = text_start_count + 1
      @provider.V4TextDelta(id="0", delta="Moon", ..) =>
        text_delta_count = text_delta_count + 1
      @provider.V4TextEnd(id="0", ..) => text_end_count = text_end_count + 1
      _ => ()
    }
  }
  assert_eq(raw_count, 4)
  assert_eq(metadata_count, 1)
  assert_eq(source_count, 1)
  assert_eq(tool_count, 1)
  assert_eq(text_start_count, 1)
  assert_eq(text_delta_count, 1)
  assert_eq(text_end_count, 1)
  assert_eq(decoder.text.to_string(), "Moon")
  assert_true(decoder.v4_finish_reason().unified is @provider.V4FinishToolCalls)
  assert_eq(decoder.v4_usage().to_usage(), {
    input_tokens: 10,
    output_tokens: 5,
    total_tokens: 15,
    reasoning_tokens: 1,
    cached_input_tokens: 2,
    cache_write_input_tokens: 1,
  })
  assert_eq(
    decoder.response_metadata_snapshot().unwrap().id,
    Some("chatcmpl_stream"),
  )
  json_inspect(decoder.provider_metadata_snapshot()["openai"], content={
    "logprobs": [{ "token": "Moon", "logprob": -0.2 }],
    "acceptedPredictionTokens": 3,
    "rejectedPredictionTokens": 1,
  })
  let v4_usage = decoder.v4_usage()
  assert_eq(v4_usage.input_tokens.no_cache, Some(7))
  assert_eq(v4_usage.input_tokens.cache_write, Some(1))
  assert_eq(v4_usage.output_tokens.reasoning, Some(1))
  assert_eq(decoder.v4_finish_reason().unified, @provider.V4FinishToolCalls)
  assert_eq(decoder.v4_finish_reason().raw, Some("tool_calls"))
}

///|
test "official OpenAI Chat flushes partial tools after stream errors" {
  let decoder = OpenAIChatStreamDecoder::new(
    include_raw_chunks=true,
    provider_name="openai.chat",
    id_generator=() => "generated-id",
  )
  let _ = decoder.feed_line(
    "data: {\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{\"}}]},\"finish_reason\":null}]}",
  )
  let _ = decoder.feed_line("")
  decoder.mark_stream_started()
  let _ = decoder.feed_line(
    "data: {\"id\":\"error-chunk\",\"model\":\"gpt-test\",\"error\":{\"message\":\"stream failed\",\"type\":\"server_error\"}}",
  )
  let error_batch = decoder.feed_line("")
  assert_false(error_batch.done)
  assert_true(error_batch.events[0] is @provider.V4Raw(_))
  assert_true(error_batch.events[1] is @provider.V4Error(_))
  assert_true(
    error_batch.events.all(event => {
      !(event is @provider.V4ResponseMetadataReady(_))
    }),
  )
  assert_true(
    error_batch.events.any(event => {
      match event {
        @provider.V4Error(error) =>
          error.message == "stream failed" &&
          error.data is Some({ "type": "server_error", .. })
        _ => false
      }
    }),
  )
  assert_false(
    error_batch.events.any(event => event is @provider.V4ToolCallReady(_)),
  )
  let terminal = decoder.finish_stream()
  assert_true(terminal.done)
  assert_true(
    terminal.events.any(event => {
      event
      is @provider.V4ToolCallReady(
        { tool_call_id: "call_1", tool_name: "lookup", input: "{", .. }
      )
    }),
  )
  assert_true(
    terminal.events.any(event => {
      event
      is @provider.V4Finish(
        reason={ unified: @provider.V4FinishError, raw: None },
        ..
      )
    }),
  )
  assert_true(decoder.v4_finish_reason().unified is @provider.V4FinishError)
  assert_eq(decoder.tools.calls().length(), 1)
}

///|
test "official OpenAI Chat validates first tool-call delta type and id" {
  let invalid_type = OpenAIChatStreamDecoder::new(
    include_raw_chunks=false,
    provider_name="openai.chat",
    id_generator=() => "generated-id",
  )
  let _ = invalid_type.feed_line(
    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"custom\",\"function\":{\"name\":\"lookup\"}}]}}]}",
  )
  try invalid_type.feed_line("") catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_eq(message, "Expected 'function' type.")
      assert_true(data is { "type": "custom", .. })
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected an invalid tool-call type error")
  }
  let missing_id = OpenAIChatStreamDecoder::new(
    include_raw_chunks=false,
    provider_name="openai.chat",
    id_generator=() => "must-not-be-used",
  )
  let _ = missing_id.feed_line(
    "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"name\":\"lookup\"}}]}}]}",
  )
  try missing_id.feed_line("") catch {
    @provider.InvalidResponseDataError(message~, ..) =>
      assert_eq(message, "Expected 'id' to be a string.")
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected a missing tool-call id error")
  }
}

///|
test "official OpenAI Chat turns malformed chunks into stream errors" {
  let decoder = OpenAIChatStreamDecoder::new(
    include_raw_chunks=true,
    provider_name="openai.chat",
    id_generator=() => "generated-id",
  )
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
