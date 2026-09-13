///|
fn moonshot_test_decoder() -> MoonshotStreamDecoder {
  MoonshotStreamDecoder::new(
    include_raw_chunks=false,
    provider_name="moonshotai.chat",
    id_generator=@provider_utils.generate_id,
  )
}

///|
fn moonshot_feed(
  decoder : MoonshotStreamDecoder,
  payload : String,
) -> Array[@provider.LanguageModelV4StreamPart] raise {
  // One physical `data:` line closed by a blank line, like the transport.
  decoder.feed_line("data: " + payload) |> ignore
  decoder.feed_line("").events
}

///|
fn moonshot_event_kinds(
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Array[String] {
  let kinds : Array[String] = []
  for event in events {
    match event {
      @provider.V4ResponseMetadataReady(_) => kinds.push("metadata")
      @provider.V4ReasoningStart(..) => kinds.push("reasoning-start")
      @provider.V4ReasoningDelta(..) => kinds.push("reasoning-delta")
      @provider.V4ReasoningEnd(..) => kinds.push("reasoning-end")
      @provider.V4TextStart(..) => kinds.push("text-start")
      @provider.V4TextDelta(..) => kinds.push("text-delta")
      @provider.V4TextEnd(..) => kinds.push("text-end")
      @provider.V4ToolCallReady(_) => kinds.push("tool-ready")
      @provider.V4ToolInputDelta(..) => kinds.push("tool-input-delta")
      @provider.V4Finish(..) => kinds.push("finish")
      @provider.V4Error(_) => kinds.push("error")
      _ => kinds.push("other")
    }
  }
  kinds
}

///|
test "Moonshot stream interleaves reasoning and text lifecycle" {
  let decoder = moonshot_test_decoder()
  let kinds : Array[String] = []
  for
    payload in [
      "{\"id\":\"c1\",\"model\":\"kimi-k2.5\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"reasoning_content\":\"thinking\"}}]}",
      "{\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"answer\"}}]}",
      "{\"id\":\"c1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
      "[DONE]",
    ] {
    for event in moonshot_feed(decoder, payload).iter() {
      kinds.append(moonshot_event_kinds([event]))
    }
  }
  assert_eq(kinds, [
    "metadata", "reasoning-start", "reasoning-delta", "text-start", "reasoning-end",
    "text-delta", "text-end", "finish",
  ])
}

///|
test "Moonshot stream prefers top-level usage over choice usage" {
  let decoder = moonshot_test_decoder()
  moonshot_feed(
    decoder, "{\"choices\":[{\"index\":0,\"delta\":{},\"usage\":{\"prompt_tokens\":9,\"completion_tokens\":2}}]}",
  )
  |> ignore
  moonshot_feed(
    decoder, "{\"usage\":{\"prompt_tokens\":11,\"completion_tokens\":3},\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
  )
  |> ignore
  let events = moonshot_feed(decoder, "[DONE]")
  let finish = match events[0] {
    @provider.V4Finish(usage~, ..) => usage
    _ => fail("expected finish part")
  }
  assert_eq(finish.input_tokens.total, Some(11))
  assert_eq(finish.output_tokens.total, Some(3))
}

///|
test "Moonshot classifies in-band stream errors with retry metadata" {
  let decoder = moonshot_test_decoder()
  let events = moonshot_feed(
    decoder, "{\"error\":{\"message\":\"Too many requests\",\"type\":\"rate_limit_exceeded\"}}",
  )
  assert_eq(moonshot_event_kinds(events), ["error"])
  match events[0] {
    @provider.V4Error(info) => {
      assert_eq(info.message, "Too many requests")
      let data = info.data.unwrap().stringify()
      assert_true(data.contains("\"statusCode\":429"))
      assert_true(data.contains("\"isRetryable\":true"))
    }
    _ => fail("expected error part")
  }
}

///|
test "Moonshot stream stitches indexless tool call deltas" {
  let decoder = moonshot_test_decoder()
  moonshot_feed(
    decoder, "{\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"lookup\",\"arguments\":\"\"}}]}}]}",
  )
  |> ignore
  let events = moonshot_feed(
    decoder, "{\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"function\":{\"arguments\":\"{\\\"city\\\"}\"}}]}}]}",
  )
  moonshot_feed(decoder, "[DONE]") |> ignore
  let kinds = moonshot_event_kinds(events)
  assert_true(kinds.contains("tool-input-delta"))
}

///|
test "Moonshot generate decode orders reasoning, tool calls, then text" {
  let decoded = decode_moonshot_chat_response(
    {
      "id": "c1",
      "object": "chat.completion",
      "created": 1700000000,
      "model": "kimi-k2.5",
      "choices": [
        {
          "index": 0,
          "message": {
            "role": "assistant",
            "reasoning_content": "because",
            "content": "answer",
            "tool_calls": [
              {
                "id": "",
                "type": "function",
                "function": { "name": "lookup", "arguments": "{}" },
              },
            ],
          },
          "finish_reason": "tool_calls",
          "logprobs": null,
        },
      ],
      "usage": {
        "prompt_tokens": 5,
        "completion_tokens": 7,
        "completion_tokens_details": { "reasoning_tokens": 7 },
      },
    },
    provider_name="moonshotai.chat",
    id_generator=@provider_utils.generate_id,
  )
  let kinds : Array[String] = []
  for part in decoded.content {
    match part {
      @provider.V4ReasoningOutput(_) => kinds.push("reasoning")
      @provider.V4ToolCallOutput(_) => kinds.push("tool-call")
      @provider.V4TextOutput(_) => kinds.push("text")
      _ => kinds.push("other")
    }
  }
  assert_eq(kinds, ["reasoning", "tool-call", "text"])
  assert_eq(decoded.finish_reason.unified, @provider.V4FinishToolCalls)
  // Reasoning tokens exceeding the completion total clamp the text share.
  assert_eq(decoded.usage.output_tokens.text, Some(0))
  assert_eq(decoded.usage.output_tokens.reasoning, Some(7))
  match decoded.provider_metadata.get("moonshotai.chat") {
    Some(Object(fields)) => {
      assert_eq(
        fields.get("responseObject").unwrap(),
        Json::string("chat.completion"),
      )
      assert_eq(fields.get("choiceIndex").unwrap(), Json::number(0.0))
      assert_eq(fields.get("messageRole").unwrap(), Json::string("assistant"))
    }
    _ => fail("expected moonshotai.chat provider metadata")
  }
}

///|
test "Moonshot finish reason mapping covers tool call spellings" {
  assert_eq(moonshot_finish_reason("tool_calls"), @provider.ToolCalls)
  assert_eq(moonshot_finish_reason("function_call"), @provider.ToolCalls)
  assert_eq(moonshot_finish_reason("content_filter"), @provider.ContentFilter)
  assert_eq(moonshot_finish_reason("length"), @provider.Length)
  assert_eq(moonshot_finish_reason("stop"), @provider.Stop)
  assert_true(moonshot_finish_reason("weird") is @provider.Unknown(_))
}

///|
test "Moonshot usage clamps negative text share" {
  let usage = convert_moonshotai_chat_usage(
    Some({
      "prompt_tokens": 10,
      "completion_tokens": 4,
      "cached_tokens": 3,
      "completion_tokens_details": { "reasoning_tokens": 9 },
    }),
  )
  assert_eq(usage.input_tokens.cache_read, Some(3))
  assert_eq(usage.input_tokens.no_cache, Some(7))
  assert_eq(usage.output_tokens.text, Some(0))
  assert_eq(usage.output_tokens.reasoning, Some(9))
}
