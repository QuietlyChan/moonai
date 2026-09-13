///|
test "perplexity finish reason mapping covers openai-style raw values" {
  assert_eq(perplexity_map_finish_reason(Some("stop")), {
    unified: @provider.V4FinishStop,
    raw: Some("stop"),
  })
  assert_eq(perplexity_map_finish_reason(Some("content_filter")), {
    unified: @provider.V4FinishContentFilter,
    raw: Some("content_filter"),
  })
  assert_eq(perplexity_map_finish_reason(None), {
    unified: @provider.V4FinishOther,
    raw: None,
  })
}

///|
test "perplexity response metadata extracts id/model/created" {
  let metadata = perplexity_response_metadata({
    "id": "resp-1",
    "model": "sonar",
    "created": 1727000000,
  })
  assert_eq(metadata.id, Some("resp-1"))
  assert_eq(metadata.model_id, Some("sonar"))
  assert_eq(metadata.created_at, Some(1727000000))
}

///|
test "perplexity provider metadata maps usage cost and images" {
  let metadata = perplexity_provider_metadata({
    "usage": {
      "prompt_tokens": 10,
      "citation_tokens": 4,
      "num_search_queries": 2,
      "cost": { "input_tokens_cost": 0.001, "total_cost": 0.002 },
    },
    "images": [
      {
        "image_url": "https://img",
        "origin_url": "https://origin",
        "height": 100,
        "width": 200,
      },
    ],
  })
  guard metadata.get("perplexity") is Some(Object(fields)) else {
    fail("expected perplexity metadata")
  }
  assert_true(
    fields.get("usage")
    is Some({ "citationTokens": 4, "numSearchQueries": 2, .. }),
  )
  assert_true(fields.get("cost") is Some({ "inputTokensCost": 0.001, .. }))
  assert_true(fields.get("images") is Some([_, ..]))
}

///|
test "perplexity citations extraction" {
  assert_eq(perplexity_citations({ "citations": ["https://a", "https://b"] }), [
    "https://a", "https://b",
  ])
  assert_eq(perplexity_citations({}), [])
}

///|
test "perplexity embedding decode maps int8 and binary payloads" {
  // "AAE=" is bytes [0, 1]; "/wA=" is bytes [255, 0] => int8 [-1, 0].
  assert_eq(perplexity_decode_embedding("AAE=", false), [0.0, 1.0])
  assert_eq(perplexity_decode_embedding("/wA=", false), [-1.0, 0.0])
  assert_eq(perplexity_decode_embedding("/wA=", true), [255.0, 0.0])
}
