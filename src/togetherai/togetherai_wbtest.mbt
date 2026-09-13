///|
test "togetherai image request body maps size and input image" {
  let body = togetherai_image_request_body(
    "black-forest-labs/FLUX.1-kontext-pro",
    prompt=Some("a red apple on a table"),
    seed=Some(7),
    n=2,
    size=Some("1024x768"),
    image_url=Some("data:image/png;base64,aGVsbG8="),
    provider_options=Map([("steps", Json::number(4))]),
  )
  assert_true(
    body
    is {
      "model": "black-forest-labs/FLUX.1-kontext-pro",
      "prompt": "a red apple on a table",
      "seed": 7,
      "n": 2,
      "width": 1024,
      "height": 768,
      "image_url": "data:image/png;base64,aGVsbG8=",
      "response_format": "base64",
      "steps": 4,
      ..
    },
  )
}

///|
test "togetherai image body omits single call n and invalid sizes" {
  let body = togetherai_image_request_body(
    "black-forest-labs/FLUX.1-schnell",
    prompt=Some("a cat"),
    seed=None,
    n=1,
    size=Some("wide"),
    image_url=None,
    provider_options=Map([]),
  )
  let wire = body.stringify()
  assert_false(wire.contains("\"n\""))
  assert_false(wire.contains("\"seed\""))
  assert_false(wire.contains("width"))
}

///|
test "togetherai parses positive dimensions only" {
  assert_eq(togetherai_parse_dimension("1024"), Some(1024))
  assert_eq(togetherai_parse_dimension("0"), None)
  assert_eq(togetherai_parse_dimension("wide"), None)
}

///|
test "togetherai image response decode maps b64 payloads" {
  let images = decode_togetherai_image_response({
    "data": [{ "b64_json": "aGVsbG8=" }, { "b64_json": "dw==" }],
  })
  assert_eq(images.length(), 2)
  assert_eq(images[0].data, @provider.ImageData::Base64("aGVsbG8="))
  assert_eq(decode_togetherai_image_response({ "data": [] }).length(), 0)
  try decode_togetherai_image_response({ "nope": 1 }) catch {
    _ => assert_true(true)
  } noraise {
    _ => fail("expected decode failure for missing data")
  }
}

///|
test "togetherai rerank response decode maps rankings" {
  let rankings = decode_togetherai_rerank_response({
    "results": [
      { "index": 2, "relevance_score": 0.98 },
      { "index": 0, "relevance_score": 0.12 },
    ],
  })
  assert_eq(rankings, [
    @provider.RerankingModelV4Ranking::new(2, 0.98),
    @provider.RerankingModelV4Ranking::new(0, 0.12),
  ])
  assert_eq(json_string_field({ "id": "abc" }, "id"), Some("abc"))
  assert_eq(json_string_field({ "id": 1 }, "id"), None)
}
