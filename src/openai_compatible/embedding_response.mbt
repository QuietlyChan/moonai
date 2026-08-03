///|
fn embedding_response_error_message(json : Json) -> String? {
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "error": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn decode_embedding_vector(json : Json) -> Array[Double] raise {
  let values : Array[Double] = []
  match json {
    Array(items) =>
      for item in items {
        match item {
          Number(value, ..) => values.push(value)
          _ => fail("embedding response contains a non-number value")
        }
      }
    _ => fail("embedding response item has no vector")
  }
  values
}

///|
fn embedding_usage_from_json(json : Json) -> @moonai.Usage {
  let input_tokens = @provider_utils.json_int_field(json, "prompt_tokens")
  {
    input_tokens,
    output_tokens: 0,
    total_tokens: input_tokens,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
  }
}

///|
/// Decode one non-streaming OpenAI-compatible embeddings response.
pub fn decode_embedding_response(
  json : Json,
) -> @moonai.EmbeddingBatchResponse raise {
  if embedding_response_error_message(json) is Some(message) {
    fail("OpenAI-compatible embedding request failed: \{message}")
  }
  let data = match json {
    { "data": Array(items), .. } => items
    _ => fail("OpenAI-compatible embedding response has no data")
  }
  let embeddings : Array[Array[Double]] = []
  for item in data {
    match item {
      { "embedding": vector, .. } =>
        embeddings.push(decode_embedding_vector(vector))
      _ => fail("OpenAI-compatible embedding item has no embedding")
    }
  }
  let usage = match json {
    { "usage": value, .. } if !(value is Null) =>
      embedding_usage_from_json(value)
    _ => @moonai.Usage::zero()
  }
  { embeddings, usage }
}
