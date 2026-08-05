///|
/// Official OpenAI embeddings model.
pub struct OpenAIEmbeddingModel {
  priv provider_name : String
  priv base_url : String
  priv model_id : String
  priv api_key : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
fn openai_embedding_model(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> OpenAIEmbeddingModel {
  {
    provider_name: "\{provider_name}.embedding",
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
    api_key,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn OpenAIEmbeddingModel::embeddings_url(self : OpenAIEmbeddingModel) -> String {
  @provider_utils.append_path(self.base_url, "/embeddings")
}

///|
fn OpenAIEmbeddingModel::request_headers(
  self : OpenAIEmbeddingModel,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    ["moonai/openai/\{VERSION}"],
  )
}

///|
fn openai_embedding_request(
  model_id : String,
  values : Array[String],
  call_options : @provider.EmbeddingOptions,
  provider_options : OpenAIEmbeddingOptions,
) -> Json {
  let dimensions = match provider_options.dimensions {
    Some(value) => Some(value)
    None => call_options.dimensions
  }
  let user = match provider_options.user {
    Some(value) => Some(value)
    None => call_options.user
  }
  Json::object(
    Map(
      [
        ("model", Json::string(model_id)),
        ("input", Json::array([ for value in values => Json::string(value) ])),
        ("encoding_format", Json::string("float")),
        ..if dimensions is Some(value) {
          [("dimensions", Json::number(value.to_double()))]
        },
        ..if user is Some(value) {
          [("user", Json::string(value))]
        },
      ],
    ),
  )
}

///|
fn openai_embedding_vector(json : Json) -> Array[Double] raise {
  let result : Array[Double] = []
  match json {
    Array(values) =>
      for value in values {
        match value {
          Number(number, ..) => result.push(number)
          _ =>
            raise @provider.InvalidResponseDataError(
              message="OpenAI embedding response contains a non-number value",
              data=json,
            )
        }
      }
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI embedding item has no vector",
        data=json,
      )
  }
  result
}

///|
fn decode_openai_embedding_response(
  json : Json,
) -> @provider.EmbeddingBatchResponse raise {
  if openai_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI embedding request failed: \{message}",
      data=json,
    )
  }
  let items = match json {
    { "data": Array(values), .. } => values
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI embedding response has no data",
        data=json,
      )
  }
  let embeddings : Array[Array[Double]] = []
  for item in items {
    match item {
      { "embedding": value, .. } =>
        embeddings.push(openai_embedding_vector(value))
      _ =>
        raise @provider.InvalidResponseDataError(
          message="OpenAI embedding item has no embedding",
          data=json,
        )
    }
  }
  let input_tokens = match json {
    { "usage": usage, .. } =>
      @provider_utils.json_int_field(usage, "prompt_tokens")
    _ => 0
  }
  @provider.EmbeddingBatchResponse::new(embeddings, {
    input_tokens,
    output_tokens: 0,
    total_tokens: input_tokens,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  })
}

///|
pub impl @provider.EmbeddingWireModel for OpenAIEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingWireModel for OpenAIEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingWireModel for OpenAIEmbeddingModel with fn max_embeddings_per_call(
  _self,
) -> Int {
  2048
}

///|
pub impl @provider.EmbeddingWireModel for OpenAIEmbeddingModel with fn supports_parallel_calls(
  _self,
) -> Bool {
  true
}

///|
pub impl @provider.EmbeddingWireModel for OpenAIEmbeddingModel with fn embed(
  self,
  values,
  call_options,
) {
  self.embed_values(values, call_options)
}

///|
async fn OpenAIEmbeddingModel::embed_values(
  self : OpenAIEmbeddingModel,
  values : Array[String],
  call_options : @provider.EmbeddingOptions,
) -> @provider.EmbeddingBatchResponse {
  guard values.length() <= 2048 else {
    raise @provider.TooManyEmbeddingValuesForCallError(
      provider=self.provider_name,
      model_id=self.model_id,
      max_embeddings_per_call=2048,
      values=values.copy(),
    )
  }
  let parsed = parse_openai_embedding_options(call_options, self.provider_name)
  let cancellation_token = call_options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.embeddings_url(),
    headers=@provider_utils.merge_headers(
      self.request_headers(),
      call_options.headers,
    ),
    body=openai_embedding_request(
      self.model_id,
      values,
      call_options,
      parsed.options,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=call_options.retry_policy,
    cancellation_token?,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  decode_openai_embedding_response(response.value)
  .with_diagnostics(None, None, Map([]), parsed.warnings)
  .with_transport(response.request, response.response)
}

///|
/// Versioned V4 boundary for the official OpenAI embedding model.
pub impl @provider.EmbeddingModelV4 for OpenAIEmbeddingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.EmbeddingModelV4 for OpenAIEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingModelV4 for OpenAIEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingModelV4 for OpenAIEmbeddingModel with fn max_embeddings_per_call(
  _self,
) -> Int? {
  Some(2048)
}

///|
pub impl @provider.EmbeddingModelV4 for OpenAIEmbeddingModel with fn supports_parallel_calls(
  _self,
) -> Bool {
  true
}

///|
pub impl @provider.EmbeddingModelV4 for OpenAIEmbeddingModel with fn do_embed(
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
