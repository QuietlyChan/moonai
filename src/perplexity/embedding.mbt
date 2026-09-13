///|
/// The Perplexity embedding model. The API only returns quantized
/// Base64-encoded vectors, decoded into numeric embeddings:
/// - `base64_int8` (default): signed int8 values (cosine similarity).
/// - `base64_binary`: packed bits per byte (Hamming distance).
struct PerplexityEmbeddingModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
/// Maximum embeddings Perplexity accepts per call.
pub const PERPLEXITY_MAX_EMBEDDINGS_PER_CALL : Int = 512

///|
fn perplexity_embedding_value(
  model_id : PerplexityEmbeddingModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> PerplexityEmbeddingModel {
  {
    provider_name: "perplexity.embedding",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
/// Decode a Base64 quantized embedding payload into numeric values.
fn perplexity_decode_embedding(
  base64 : String,
  binary : Bool,
) -> Array[Double] raise {
  let bytes = @base64.decode(base64)
  let values : Array[Double] = []
  for byte in bytes {
    let value = byte.to_int()
    if binary {
      values.push(value.to_double())
    } else if value < 128 {
      values.push(value.to_double())
    } else {
      values.push((value - 256).to_double())
    }
  }
  values
}

///|
fn perplexity_embedding_response(
  value : Json,
) -> (Array[Array[Double]], Int?) raise {
  match value {
    { "data": Array(items), .. } => {
      let embeddings : Array[Array[Double]] = []
      let mut binary = false
      if value is Object(fields) {
        match fields.get("encoding_format") {
          Some(String("base64_binary")) => binary = true
          _ => ()
        }
      }
      for item in items {
        match item {
          { "embedding": String(payload), .. } =>
            embeddings.push(perplexity_decode_embedding(payload, binary))
          _ => fail("perplexity embedding response has malformed data items")
        }
      }
      let mut tokens : Int? = None
      match value {
        { "usage": { "prompt_tokens": Number(count, ..), .. }, .. } =>
          tokens = Some(count.to_int())
        _ => ()
      }
      (embeddings, tokens)
    }
    _ => fail("perplexity embedding response missing data")
  }
}

///|
pub impl @provider.EmbeddingModelV4 for PerplexityEmbeddingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.EmbeddingModelV4 for PerplexityEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingModelV4 for PerplexityEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingModelV4 for PerplexityEmbeddingModel with fn max_embeddings_per_call(
  _self,
) -> Int? {
  Some(PERPLEXITY_MAX_EMBEDDINGS_PER_CALL)
}

///|
pub impl @provider.EmbeddingModelV4 for PerplexityEmbeddingModel with fn supports_parallel_calls(
  _self,
) -> Bool {
  true
}

///|
pub impl @provider.EmbeddingModelV4 for PerplexityEmbeddingModel with fn max_input_bytes_per_call(
  _self,
) -> Int64? {
  None
}

///|
pub impl @provider.EmbeddingModelV4 for PerplexityEmbeddingModel with fn do_embed(
  self,
  options,
) {
  guard options.values.length() <= PERPLEXITY_MAX_EMBEDDINGS_PER_CALL else {
    raise @provider.TooManyEmbeddingValuesForCallError(
      provider=self.provider_name,
      model_id=self.model_id,
      max_embeddings_per_call=PERPLEXITY_MAX_EMBEDDINGS_PER_CALL,
      values=options.values,
    )
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
  )
  let mut encoding_format = "base64_int8"
  let dimensions : Map[String, Json] = Map([])
  for entry in resolution.values.iter2() {
    match entry.0 {
      "encodingFormat" =>
        match entry.1 {
          String("base64_binary") => encoding_format = "base64_binary"
          String("base64_int8") => encoding_format = "base64_int8"
          _ => ()
        }
      "dimensions" => dimensions["dimensions"] = entry.1
      _ => ()
    }
  }
  let fields : Map[String, Json] = Map([
    ("model", Json::string(self.model_id)),
    (
      "input",
      Json::array([ for value in options.values => Json::string(value) ]),
    ),
    ("encoding_format", Json::string(encoding_format)),
  ])
  for entry in dimensions.iter2() {
    fields[entry.0] = entry.1
  }
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/v1/embeddings"),
    headers=perplexity_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
    ),
    body=Json::object(fields),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=perplexity_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (embeddings, tokens) = @provider_utils.handle_json_response(
    response, perplexity_embedding_response,
  )
  let cost_metadata : Map[String, Json] = match response.value {
    { "usage": { "cost": Object(cost), .. }, .. } => {
      let mapped : Map[String, Json] = Map([])
      for
        pair in [
          ("input_cost", "inputCost"),
          ("total_cost", "totalCost"),
          ("currency", "currency"),
        ] {
        if cost.get(pair.0) is Some(v) {
          mapped[pair.1] = v
        }
      }
      Map([("perplexity", Json::object({ "cost": Json::object(mapped) }))])
    }
    _ => Map([])
  }
  @provider.EmbeddingModelV4Result::new(
    embeddings,
    usage?=tokens.map(@provider.EmbeddingModelV4Usage::new),
    provider_metadata=cost_metadata,
    request=response.request,
    response=response.response,
  )
}
