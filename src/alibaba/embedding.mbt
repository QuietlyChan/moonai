///|
/// Native DashScope text embedding model.
pub struct AlibabaEmbeddingModel {
  priv provider_name : String
  priv base_url : String
  priv api_key : String
  priv model_id : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct a native Alibaba text embedding model.
pub fn alibaba_embedding(
  model_id : AlibabaEmbeddingModelId,
  api_key? : String = "",
  base_url? : String = "https://dashscope-intl.aliyuncs.com/api/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> AlibabaEmbeddingModel {
  {
    provider_name: "alibaba.embedding",
    base_url: @provider_utils.without_trailing_slash(base_url),
    api_key,
    model_id,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
fn AlibabaEmbeddingModel::request_headers(
  self : AlibabaEmbeddingModel,
  options : @provider.EmbeddingOptions,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer \{load_alibaba_api_key(self.api_key)}"
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      ["moonai/alibaba/\{VERSION}"],
    ),
    options.headers,
  )
}

///|
fn AlibabaEmbeddingModel::embedding_url(self : AlibabaEmbeddingModel) -> String {
  @provider_utils.append_path(
    self.base_url,
    "/services/embeddings/text-embedding/text-embedding",
  )
}

///|
fn embedding_texts(json : Json) -> Array[(Int, Array[Double], Json?)] raise {
  match json {
    { "output": { "embeddings": Array(values), .. }, .. } => {
      let result : Array[(Int, Array[Double], Json?)] = []
      for value in values {
        match value {
          { "embedding": Array(numbers), "text_index": Number(index, ..), .. } => {
            let vector : Array[Double] = []
            for number in numbers {
              match number {
                Number(value, ..) => vector.push(value)
                _ =>
                  raise @provider.InvalidResponseDataError(
                    message="Alibaba embedding contains a non-number value",
                    data=json,
                  )
              }
            }
            let sparse = match value {
              { "sparse_embedding": sparse_value, .. } => Some(sparse_value)
              _ => None
            }
            result.push((index.to_int(), vector, sparse))
          }
          _ =>
            raise @provider.InvalidResponseDataError(
              message="Alibaba embedding response contains an invalid embedding",
              data=json,
            )
        }
      }
      result
    }
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Alibaba embedding response has no output.embeddings array",
        data=json,
      )
  }
}

///|
fn sort_embedding_values(
  values : Array[(Int, Array[Double], Json?)],
) -> Array[(Int, Array[Double], Json?)] {
  let result : Array[(Int, Array[Double], Json?)] = []
  for value in values {
    let mut index = 0
    while index < result.length() && result[index].0 <= value.0 {
      index = index + 1
    }
    result.push(value)
    let mut current = result.length() - 1
    while current > index {
      result[current] = result[current - 1]
      current = current - 1
    }
    result[index] = value
  }
  result
}

///|
async fn AlibabaEmbeddingModel::embed_values(
  self : AlibabaEmbeddingModel,
  values : Array[String],
  options : @provider.EmbeddingOptions,
) -> @provider.EmbeddingBatchResponse {
  let (provider_options, option_warnings) = parse_alibaba_embedding_options(
    options.provider_options,
  )
  let cancellation_token = options.cancellation_token
  if provider_options.output_type == Some("sparse") {
    raise @provider.UnsupportedFunctionalityError(
      functionality="Alibaba embedding outputType 'sparse' is not supported; use 'dense' or 'dense&sparse'",
    )
  }
  let parameters : Map[String, Json] = Map([])
  match provider_options.text_type {
    Some(value) => parameters["text_type"] = Json::string(value)
    None => ()
  }
  let dimension = match provider_options.dimension {
    Some(value) => Some(value)
    None => options.dimensions
  }
  match dimension {
    Some(value) => parameters["dimension"] = Json::number(value.to_double())
    None => ()
  }
  match provider_options.output_type {
    Some(value) => parameters["output_type"] = Json::string(value)
    None => ()
  }
  let body : Json = {
    "model": self.model_id,
    "input": {
      "texts": Json::array([ for value in values => Json::string(value) ]),
    },
    "parameters": Json::object(parameters),
  }
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.embedding_url(),
    headers=self.request_headers(options),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=alibaba_native_error_message,
    transport=self.http_transport,
  )
  let records = sort_embedding_values(embedding_texts(response.value))
  let embeddings : Array[Array[Double]] = [ for record in records => record.1 ]
  let sparse : Array[Json] = []
  for record in records {
    match record.2 {
      Some(value) =>
        sparse.push({ "textIndex": record.0, "sparseEmbedding": value })
      None => ()
    }
  }
  let metadata : Map[String, Json] = Map([])
  if sparse.length() > 0 {
    metadata["alibaba"] = { "sparseEmbeddings": Json::array(sparse) }
  }
  let usage = match response.value {
    { "usage": usage, .. } => convert_alibaba_embedding_usage(usage)
    _ => @provider.Usage::zero()
  }
  @provider.EmbeddingBatchResponse::new(embeddings, usage)
  .with_diagnostics(None, None, metadata, option_warnings)
  .with_transport(response.request, response.response)
}

///|
fn alibaba_native_error_message(json : Json) -> String? {
  match json {
    { "message": String(message), .. } => Some(message)
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}

///|
pub impl @provider.EmbeddingWireModel for AlibabaEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingWireModel for AlibabaEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingWireModel for AlibabaEmbeddingModel with fn max_embeddings_per_call(
  _self,
) -> Int {
  10
}

///|
/// DashScope embedding requests are serialized to avoid provider throttling.
pub impl @provider.EmbeddingWireModel for AlibabaEmbeddingModel with fn supports_parallel_calls(
  _self,
) -> Bool {
  false
}

///|
pub impl @provider.EmbeddingWireModel for AlibabaEmbeddingModel with fn embed(
  self,
  values,
  options,
) {
  guard values.length() <= 10 else {
    raise @provider.TooManyEmbeddingValuesForCallError(
      provider=self.provider_name,
      model_id=self.model_id,
      max_embeddings_per_call=10,
      values=values.copy(),
    )
  }
  self.embed_values(values, options)
}

///|
/// Versioned V4 boundary for DashScope embeddings.
pub impl @provider.EmbeddingModelV4 for AlibabaEmbeddingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.EmbeddingModelV4 for AlibabaEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingModelV4 for AlibabaEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingModelV4 for AlibabaEmbeddingModel with fn max_embeddings_per_call(
  _self,
) -> Int? {
  Some(10)
}

///|
pub impl @provider.EmbeddingModelV4 for AlibabaEmbeddingModel with fn supports_parallel_calls(
  _self,
) -> Bool {
  false
}

///|
pub impl @provider.EmbeddingModelV4 for AlibabaEmbeddingModel with fn do_embed(
  self,
  options,
) {
  let legacy_options = @provider.EmbeddingOptions::new(
    dimensions?=None,
    user?=None,
    headers=options.headers,
    provider_options=options.provider_options,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
  @provider.EmbeddingModelV4Result::from_batch_response(
    self.embed_values(options.values, legacy_options),
  )
}
