///|
/// Native DashScope text embedding model.
priv struct AlibabaEmbeddingModel {
  provider_name : String
  base_url : String
  api_key : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct the concrete embedding model behind the public V4 boundary.
fn alibaba_embedding_value(
  model_id : AlibabaEmbeddingModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> AlibabaEmbeddingModel {
  {
    provider_name: "alibaba.embedding",
    base_url: @provider_utils.without_trailing_slash(base_url),
    api_key,
    model_id,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn AlibabaEmbeddingModel::request_headers_with(
  self : AlibabaEmbeddingModel,
  request_headers : Map[String, String],
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
    request_headers,
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
fn alibaba_sparse_embedding(value : Json, response : Json) -> Json? raise {
  match value {
    { "sparse_embedding": Null, .. } => None
    { "sparse_embedding": Array(items), .. } => {
      let normalized : Array[Json] = []
      for item in items {
        match item {
          { "index": Number(index, ..), "value": Number(weight, ..), .. } => {
            let fields : Map[String, Json] = Map([
              ("index", Json::number(index)),
              ("value", Json::number(weight)),
            ])
            match item {
              { "token": String(token), .. } =>
                fields["token"] = Json::string(token)
              { "token": Null, .. } | _ => ()
            }
            normalized.push(Json::object(fields))
          }
          _ =>
            raise @provider.InvalidResponseDataError(
              message="Alibaba sparse embedding contains an invalid entry",
              data=response,
            )
        }
      }
      Some(Json::array(normalized))
    }
    { "sparse_embedding": _, .. } =>
      raise @provider.InvalidResponseDataError(
        message="Alibaba sparse embedding must be an array or null",
        data=response,
      )
    _ => None
  }
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
            let sparse = alibaba_sparse_embedding(value, json)
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
priv struct AlibabaEmbeddingCoreResult {
  embeddings : Array[Array[Double]]
  usage_tokens : Int?
  provider_metadata : Map[String, Json]
  warnings : Array[@provider.Warning]
  request : @provider.RequestMetadata
  response : @provider.ResponseMetadata
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
async fn AlibabaEmbeddingModel::perform_embedding_request(
  self : AlibabaEmbeddingModel,
  values : Array[String],
  request_headers : Map[String, String],
  raw_provider_options : Map[String, Json],
  fallback_dimension : Int?,
  retry_policy : @provider.RetryPolicy,
  cancellation_token : @provider.CancellationToken?,
) -> AlibabaEmbeddingCoreResult {
  let (provider_options, option_warnings) = parse_alibaba_embedding_options(
    raw_provider_options,
  )
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
    None => fallback_dimension
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
    headers=self.request_headers_with(request_headers),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy~,
    cancellation_token?,
    error_to_message=alibaba_native_error_message,
    transport=self.http_transport,
  )
  let (records, usage_tokens) = @provider_utils.handle_json_response(response, value => {
    let records = sort_embedding_values(embedding_texts(value))
    let usage_tokens = match value {
      { "usage": Null, .. } => None
      { "usage": { "total_tokens": Number(value, ..), .. }, .. } =>
        Some(value.to_int())
      { "usage": _, .. } =>
        raise @provider.InvalidResponseDataError(
          message="Alibaba embedding response contains invalid usage",
          data=value,
        )
      _ => None
    }
    (records, usage_tokens)
  })
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
  {
    embeddings,
    usage_tokens,
    provider_metadata: metadata,
    warnings: option_warnings,
    request: response.request,
    response: response.response,
  }
}

///|
fn alibaba_native_error_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "message": String(message), .. } => Some(message)
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}

///|
/// Versioned V4 boundary for DashScope embeddings.
impl @provider.EmbeddingModelV4 for AlibabaEmbeddingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.EmbeddingModelV4 for AlibabaEmbeddingModel with fn provider(self) -> String {
  self.provider_name
}

///|
impl @provider.EmbeddingModelV4 for AlibabaEmbeddingModel with fn model_id(self) -> String {
  self.model_id
}

///|
impl @provider.EmbeddingModelV4 for AlibabaEmbeddingModel with fn max_embeddings_per_call(
  _self,
) -> Int? {
  Some(10)
}

///|
impl @provider.EmbeddingModelV4 for AlibabaEmbeddingModel with fn supports_parallel_calls(
  _self,
) -> Bool {
  false
}

///|
impl @provider.EmbeddingModelV4 for AlibabaEmbeddingModel with fn do_embed(
  self,
  options,
) {
  guard options.values.length() <= 10 else {
    raise @provider.TooManyEmbeddingValuesForCallError(
      provider=self.provider_name,
      model_id=self.model_id,
      max_embeddings_per_call=10,
      values=options.values.copy(),
    )
  }
  let result = self.perform_embedding_request(
    options.values,
    options.headers,
    options.provider_options,
    None,
    options.retry_policy,
    options.cancellation_token,
  )
  let usage = match result.usage_tokens {
    Some(value) => Some(@provider.EmbeddingModelV4Usage::new(value))
    None => None
  }
  @provider.EmbeddingModelV4Result::new(
    result.embeddings,
    usage?,
    provider_metadata=result.provider_metadata,
    request=result.request,
    response=result.response,
    warnings=result.warnings,
  )
}
