///|
fn decode_embedding_vector(json : Json) -> Array[Double] raise {
  let values : Array[Double] = []
  match json {
    Array(items) =>
      for item in items {
        match item {
          Number(value, ..) => values.push(value)
          _ =>
            raise @provider.InvalidResponseDataError(
              message="embedding response contains a non-number value",
              data=json,
            )
        }
      }
    _ =>
      raise @provider.InvalidResponseDataError(
        message="embedding response item has no vector",
        data=json,
      )
  }
  values
}

///|
fn embedding_usage_from_json(json : Json) -> @provider.Usage {
  let input_tokens = @provider_utils.json_int_field(json, "prompt_tokens")
  {
    input_tokens,
    output_tokens: 0,
    total_tokens: input_tokens,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  }
}

///|
/// Decode one non-streaming OpenAI-compatible embeddings response.
pub fn decode_embedding_response(
  json : Json,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
) -> @provider.EmbeddingBatchResponse raise {
  if error_structure.message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI-compatible embedding request failed: \{message}",
      data=json,
    )
  }
  let data = match json {
    { "data": Array(items), .. } => items
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI-compatible embedding response has no data",
        data=json,
      )
  }
  let embeddings : Array[Array[Double]] = []
  for item in data {
    match item {
      { "embedding": vector, .. } =>
        embeddings.push(decode_embedding_vector(vector))
      _ =>
        raise @provider.InvalidResponseDataError(
          message="OpenAI-compatible embedding item has no embedding",
          data=json,
        )
    }
  }
  let usage = match json {
    { "usage": value, .. } if !(value is Null) =>
      embedding_usage_from_json(value)
    _ => @provider.Usage::zero()
  }
  @provider.EmbeddingBatchResponse::new(embeddings, usage)
}
