///|
/// The AI Gateway embedding model: POST /embedding-model with the values
/// array; usage, warnings and provider metadata come back inline.
struct GatewayEmbeddingModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
/// The gateway's per-request embedding input limit.
pub const GATEWAY_MAX_EMBEDDINGS_PER_CALL : Int = 2048

///|
fn gateway_embedding_value(
  model_id : String,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> GatewayEmbeddingModel {
  {
    provider_name: "gateway",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn GatewayEmbeddingModel::embedding_headers(
  self : GatewayEmbeddingModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let resolved = gateway_base_headers(
    api_key=self.api_key,
    headers=self.headers,
    extra~,
    content_type="application/json",
    accept="application/json",
  )
  resolved["ai-embedding-model-specification-version"] = "4"
  resolved["ai-model-id"] = self.model_id
  resolved
}

///|
/// Decode the embedding response: embeddings array, token usage, warnings.
fn gateway_decode_embedding_response(
  value : Json,
) -> (Array[Array[Double]], Int?) raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match value {
    { "embeddings": Array(rows), .. } => {
      let embeddings : Array[Array[Double]] = []
      for row in rows {
        match row {
          Array(components) => {
            let embedding : Array[Double] = []
            for component in components {
              match component {
                Number(number, ..) => embedding.push(number)
                _ => fail("gateway embedding has non-numeric component")
              }
            }
            embeddings.push(embedding)
          }
          _ => fail("gateway embedding response has malformed rows")
        }
      }
      let tokens = match value {
        { "usage": { "tokens": Number(count, ..), .. }, .. } =>
          Some(count.to_int())
        _ => None
      }
      (embeddings, tokens)
    }
    _ => fail("gateway embedding response missing embeddings")
  }
}

///|
pub impl @provider.EmbeddingModelV4 for GatewayEmbeddingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.EmbeddingModelV4 for GatewayEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingModelV4 for GatewayEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingModelV4 for GatewayEmbeddingModel with fn max_embeddings_per_call(
  _self,
) -> Int? {
  Some(GATEWAY_MAX_EMBEDDINGS_PER_CALL)
}

///|
pub impl @provider.EmbeddingModelV4 for GatewayEmbeddingModel with fn supports_parallel_calls(
  _self,
) -> Bool {
  true
}

///|
pub impl @provider.EmbeddingModelV4 for GatewayEmbeddingModel with fn max_input_bytes_per_call(
  _self,
) -> Int64? {
  None
}

///|
pub impl @provider.EmbeddingModelV4 for GatewayEmbeddingModel with fn do_embed(
  self,
  options,
) {
  guard options.values.length() <= GATEWAY_MAX_EMBEDDINGS_PER_CALL else {
    raise @provider.TooManyEmbeddingValuesForCallError(
      provider=self.provider_name,
      model_id=self.model_id,
      max_embeddings_per_call=GATEWAY_MAX_EMBEDDINGS_PER_CALL,
      values=options.values,
    )
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
  )
  let fields : Map[String, Json] = Map([
    (
      "values",
      Json::array([ for value in options.values => Json::string(value) ]),
    ),
  ])
  if resolution.values.length() > 0 {
    fields["providerOptions"] = Json::object(resolution.values)
  }
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/embedding-model"),
    headers=self.embedding_headers(extra=options.headers),
    body=Json::object(fields),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=gateway_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (embeddings, tokens) = @provider_utils.handle_json_response(
    response, gateway_decode_embedding_response,
  )
  @provider.EmbeddingModelV4Result::new(
    embeddings,
    usage?=tokens.map(@provider.EmbeddingModelV4Usage::new),
    warnings=gateway_decode_warnings(
      match response.value {
        Object(fields) => fields.get("warnings")
        _ => None
      },
    ),
    request=response.request,
    response=response.response,
  )
}
