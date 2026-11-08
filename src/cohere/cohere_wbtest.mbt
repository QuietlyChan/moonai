///|
test "cohere finish reason mapping covers UPPER raw values" {
  assert_eq(cohere_map_finish_reason(Some("COMPLETE")), {
    unified: @provider.V4FinishStop,
    raw: Some("COMPLETE"),
  })
  assert_eq(cohere_map_finish_reason(Some("MAX_TOKENS")), {
    unified: @provider.V4FinishLength,
    raw: Some("MAX_TOKENS"),
  })
  assert_eq(cohere_map_finish_reason(Some("TOOL_CALL")), {
    unified: @provider.V4FinishToolCalls,
    raw: Some("TOOL_CALL"),
  })
  assert_eq(cohere_map_finish_reason(None), {
    unified: @provider.V4FinishOther,
    raw: None,
  })
}

///|
test "cohere usage prefers tokens totals" {
  let usage = cohere_usage(
    Some({
      "tokens": { "input_tokens": 12, "output_tokens": 34 },
      "billed_units": { "input_tokens": 10, "output_tokens": 30 },
    }),
  )
  assert_eq(usage.input_tokens.total, Some(12))
  assert_eq(usage.output_tokens.total, Some(34))
  assert_eq(cohere_usage(None).input_tokens.total, None)
}

///|
test "cohere usage leaves billed units out of token totals and preserves cache" {
  let usage = cohere_usage(
    Some({
      "billed_units": { "input_tokens": 12, "output_tokens": 7 },
      "cached_tokens": 4,
    }),
  )
  assert_eq(usage.input_tokens.total, None)
  assert_eq(usage.input_tokens.no_cache, None)
  assert_eq(usage.input_tokens.cache_read, Some(4))
  assert_eq(usage.output_tokens.total, None)
}

///|
test "cohere chat response id prefers v2 id and falls back to v1 generation_id" {
  assert_eq(
    cohere_chat_response_id({ "id": "v2-id", "generation_id": "v1-id" }),
    Some("v2-id"),
  )
  assert_eq(
    cohere_chat_response_id({ "generation_id": "v1-id" }),
    Some("v1-id"),
  )
  assert_eq(
    cohere_chat_response_id({ "id": Json::null(), "generation_id": "v1-id" }),
    Some("v1-id"),
  )
  assert_eq(cohere_chat_response_id({}), None)
}

///|
test "cohere reranking accepts results without response metadata" {
  assert_eq(
    decode_cohere_rerank_response({
      "results": [
        { "index": 2, "relevance_score": 0.95 },
        { "index": 0, "relevance_score": 0.42 },
      ],
    }),
    [
      @provider.RerankingModelV4Ranking::new(2, 0.95),
      @provider.RerankingModelV4Ranking::new(0, 0.42),
    ],
  )
}

///|
test "cohere citations preserve document metadata and skip tool-only sources" {
  let sources = cohere_citation_contents(
    Some(
      Json::array([
        {
          "start": 1,
          "end": 4,
          "text": "Bit",
          "sources": [
            { "type": "document", "document": { "title": "guide.txt" } },
          ],
          "type": "TEXT_CONTENT",
        },
        { "sources": [{ "type": "tool", "tool_output": { "ok": true } }] },
      ]),
    ),
    () => "citation-id",
  )
  assert_eq(sources.length(), 1)
  assert_true(
    sources[0]
    is @provider.V4SourceOutput(
      @provider.V4DocumentSource(
        id="citation-id",
        title="guide.txt",
        provider_metadata={
          "cohere": {
            "start": 1,
            "end": 4,
            "text": "Bit",
            "sources": [
              {
                "type": "document",
                "document": { "title": "guide.txt", .. },
                ..
              },
            ],
            "citationType": "TEXT_CONTENT",
            ..
          },
          ..
        },
        ..
      )
    ),
  )
}

///|
test "cohere citation stream emits document sources and tolerates missing citations" {
  let decoder = CohereStreamDecoder::new(false, () => "stream-citation-id")
  let _ = decoder.feed_line(
    "data: {\"type\":\"citation-start\",\"index\":0,\"delta\":{\"message\":{\"citations\":{\"sources\":[{\"type\":\"document\",\"document\":{}}]}}}}",
  )
  let source_events = decoder.feed_line("").events
  assert_true(source_events.any(event => event is @provider.V4SourceReady(_)))
  let _ = decoder.feed_line("data: {\"type\":\"citation-start\",\"index\":0}")
  assert_true(decoder.feed_line("").events.is_empty())
}

///|
test "cohere tool call fields extraction" {
  assert_eq(
    cohere_tool_call_fields({
      "id": "t1",
      "function": { "name": "search", "arguments": "{}" },
    }),
    ("t1", "search", "{}"),
  )
  assert_eq(cohere_tool_call_fields({}), ("", "", ""))
}

///|
test "cohere error message resolves flat payloads" {
  assert_eq(
    cohere_error_to_message({ "message": "invalid request" }),
    Some("invalid request"),
  )
  assert_eq(cohere_error_to_message({ "code": 1 }), None)
}
