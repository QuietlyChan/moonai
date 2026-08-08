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
fn decode_embedding_response_data(
  json : Json,
  error_structure : OpenAICompatibleErrorStructure,
) -> (Array[Array[Double]], Int?) raise {
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
  let usage_tokens = match json {
    { "usage": value, .. } if !(value is Null) =>
      Some(@provider_utils.json_int_field(value, "prompt_tokens"))
    _ => None
  }
  (embeddings, usage_tokens)
}
