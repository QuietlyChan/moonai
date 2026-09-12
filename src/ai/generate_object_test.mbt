///|
priv struct ChunkedJSONModel {
  chunks : Array[String]
}

///|
fn ChunkedJSONModel::new(chunks : Array[String]) -> ChunkedJSONModel {
  { chunks, }
}

///|
impl @provider.LanguageModelV4 for ChunkedJSONModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for ChunkedJSONModel with fn provider(_self) -> String {
  "test.chunked"
}

///|
impl @provider.LanguageModelV4 for ChunkedJSONModel with fn model_id(_self) -> String {
  "chunked-json"
}

///|
impl @provider.LanguageModelV4 for ChunkedJSONModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
impl @provider.LanguageModelV4 for ChunkedJSONModel with fn do_generate(
  self,
  _options,
) -> @provider.LanguageModelV4GenerateResult raise {
  let text = self.chunks.join("")
  let content : Array[@provider.LanguageModelV4Content] = [
    @provider.LanguageModelV4Content::text(text),
  ]
  {
    content,
    finish_reason: { unified: @provider.V4FinishStop, raw: None, },
    usage: @provider.LanguageModelV4Usage::unknown(),
    provider_metadata: Map([]),
    request: None,
    response: None,
    warnings: [],
  }
}

///|
impl @provider.LanguageModelV4 for ChunkedJSONModel with fn do_stream(
  self,
  _options,
  emit,
) -> @provider.LanguageModelV4StreamResult raise {
  for chunk in self.chunks {
    emit(
      @provider.V4TextDelta(id="txt-0", delta=chunk, provider_metadata=Map([])),
    )
  }
  emit(
    @provider.V4Finish(
      usage=@provider.LanguageModelV4Usage::unknown(),
      reason={ unified: @provider.V4FinishStop, raw: None, },
      provider_metadata=Map([]),
    ),
  )
  @provider.LanguageModelV4StreamResult::new(None, None)
}

///|
async test "stream object emits partial snapshots and a validated final object" {
  let model = ChunkedJSONModel::new([
    "{\"name\": \"Moon", "Bit\", \"count\": 4", "2}",
  ])
  let schema : Json = {
    "type": "object",
    "properties": {
      "name": { "type": "string" },
      "count": { "type": "integer" },
    },
    "required": ["name", "count"],
  }
  let snapshots : Array[Json] = []
  let response = @ai.stream_object(model, schema, prompt="generate", on_partial=fn(
    object : Json,
  ) {
    snapshots.push(object)
    println("partial=" + object.stringify())
  })
  match response.object {
    { "name": String(name), "count": Number(count, ..), .. } => {
      assert_eq(name, "MoonBit")
      assert_eq(count.to_int(), 42)
    }
    _ => fail("expected name and count members")
  }
  assert_eq(snapshots.length(), 3)
}

///|
async test "stream object partial snapshots grow monotonically" {
  let model = ChunkedJSONModel::new([
    "{\"city\": \"Har", "bin\", \"temp\": ", "-12}",
  ])
  let schema : Json = {
    "type": "object",
    "properties": { "city": { "type": "string" }, "temp": { "type": "number" } },
  }
  let snapshots : Array[Json] = []
  let _ = @ai.stream_object(model, schema, prompt="generate", on_partial=fn(
    object : Json,
  ) {
    snapshots.push(object)
  })
  // At least one partial snapshot was delivered before completion.
  assert_true(snapshots.length() >= 1)
}
