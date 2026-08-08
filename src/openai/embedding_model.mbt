///|
/// Official OpenAI embeddings model.
priv struct OpenAIEmbeddingModel {
  provider_name : String
  base_url : String
  model_id : String
  api_key : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
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
  dimensions : Int?,
  user : String?,
) -> Json {
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
) -> (Array[Array[Double]], Int?) raise {
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
  let usage_tokens = match json {
    { "usage": usage, .. } if !(usage is Null) =>
      Some(@provider_utils.json_int_field(usage, "prompt_tokens"))
    _ => None
  }
  (embeddings, usage_tokens)
}

///|
async fn OpenAIEmbeddingModel::perform_embedding_request(
  self : OpenAIEmbeddingModel,
  values : Array[String],
  headers : Map[String, String],
  provider_options : Map[String, Json],
  retry_policy : @provider.RetryPolicy,
  cancellation_token : @provider.CancellationToken?,
) -> @provider.EmbeddingModelV4Result {
  guard values.length() <= 2048 else {
    raise @provider.TooManyEmbeddingValuesForCallError(
      provider=self.provider_name,
      model_id=self.model_id,
      max_embeddings_per_call=2048,
      values=values.copy(),
    )
  }
  let parsed = parse_openai_embedding_provider_options(
    provider_options,
    self.provider_name,
  )
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.embeddings_url(),
    headers=@provider_utils.merge_headers(self.request_headers(), headers),
    body=openai_embedding_request(
      self.model_id,
      values,
      parsed.options.dimensions,
      parsed.options.user,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy~,
    cancellation_token?,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  let (embeddings, usage_tokens) = @provider_utils.handle_json_response(
    response, decode_openai_embedding_response,
  )
  let usage = match usage_tokens {
    Some(value) => Some(@provider.EmbeddingModelV4Usage::new(value))
    None => None
  }
  @provider.EmbeddingModelV4Result::new(
    embeddings,
    usage?,
    request=response.request,
    response=response.response,
    warnings=parsed.warnings,
  )
}

///|
/// Versioned V4 boundary for the official OpenAI embedding model.
impl @provider.EmbeddingModelV4 for OpenAIEmbeddingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.EmbeddingModelV4 for OpenAIEmbeddingModel with fn provider(self) -> String {
  self.provider_name
}

///|
impl @provider.EmbeddingModelV4 for OpenAIEmbeddingModel with fn model_id(self) -> String {
  self.model_id
}

///|
impl @provider.EmbeddingModelV4 for OpenAIEmbeddingModel with fn max_embeddings_per_call(
  _self,
) -> Int? {
  Some(2048)
}

///|
impl @provider.EmbeddingModelV4 for OpenAIEmbeddingModel with fn supports_parallel_calls(
  _self,
) -> Bool {
  true
}

///|
impl @provider.EmbeddingModelV4 for OpenAIEmbeddingModel with fn do_embed(
  self,
  options,
) {
  self.perform_embedding_request(
    options.values,
    options.headers,
    options.provider_options,
    options.retry_policy,
    options.cancellation_token,
  )
}
