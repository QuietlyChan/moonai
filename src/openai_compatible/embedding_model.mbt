///|
/// A text embedding model using the OpenAI embeddings wire protocol.
pub struct OpenAICompatibleEmbeddingModel {
  priv provider_name : String
  priv api_key : String
  priv api_key_environment_variable : String?
  priv base_url : String
  priv model_id : OpenAICompatibleEmbeddingModelId
  priv headers : Map[String, String]
  priv query_params : Map[String, String]
  priv max_embeddings : Int
  priv supports_parallel : Bool
  priv error_structure : OpenAICompatibleErrorStructure
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Construct an OpenAI-compatible embedding model directly.
pub fn openai_compatible_embedding(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : OpenAICompatibleEmbeddingModelId,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  query_params? : Map[String, String] = Map([]),
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  idle_timeout_ms? : Int = 120_000,
  max_embeddings_per_call? : Int = 2048,
  supports_parallel_calls? : Bool = true,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
) -> OpenAICompatibleEmbeddingModel {
  {
    provider_name: "\{provider_name}.embedding",
    api_key,
    api_key_environment_variable,
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
    headers: @provider_utils.copy_headers(headers),
    query_params: @provider_utils.copy_headers(query_params),
    max_embeddings: max_embeddings_per_call,
    supports_parallel: supports_parallel_calls,
    error_structure,
    idle_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
fn OpenAICompatibleEmbeddingModel::embeddings_url(
  self : OpenAICompatibleEmbeddingModel,
) -> String {
  @provider_utils.append_query(
    @provider_utils.append_path(self.base_url, "/embeddings"),
    self.query_params,
  )
}

///|
fn OpenAICompatibleEmbeddingModel::request_headers(
  self : OpenAICompatibleEmbeddingModel,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  let api_key = match self.api_key_environment_variable {
    Some(environment_variable_name) =>
      Some(
        @provider_utils.load_api_key(
          self.api_key,
          environment_variable_name~,
          description=self.provider_name,
        ),
      )
    None if self.api_key != "" => Some(self.api_key)
    None => None
  }
  match api_key {
    Some(value) => headers["Authorization"] = "Bearer \{value}"
    None => ()
  }
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    [openai_compatible_user_agent_suffix(self.provider_name)],
  )
}

///|
pub impl @provider.EmbeddingWireModel for OpenAICompatibleEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingWireModel for OpenAICompatibleEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingWireModel for OpenAICompatibleEmbeddingModel with fn max_embeddings_per_call(
  self,
) -> Int {
  self.max_embeddings
}

///|
pub impl @provider.EmbeddingWireModel for OpenAICompatibleEmbeddingModel with fn supports_parallel_calls(
  self,
) -> Bool {
  self.supports_parallel
}

///|
pub impl @provider.EmbeddingWireModel for OpenAICompatibleEmbeddingModel with fn embed(
  self,
  values,
  options,
) {
  self.embed_values(values, options)
}

///|
async fn OpenAICompatibleEmbeddingModel::embed_values(
  self : OpenAICompatibleEmbeddingModel,
  values : Array[String],
  options : @provider.EmbeddingOptions,
) -> @provider.EmbeddingBatchResponse {
  guard values.length() <= self.max_embeddings else {
    raise @provider.TooManyEmbeddingValuesForCallError(
      provider=self.provider_name,
      model_id=self.model_id,
      max_embeddings_per_call=self.max_embeddings,
      values=values.copy(),
    )
  }
  let request_body = encode_embedding_request(
    self.model_id,
    values,
    options,
    provider_name=self.provider_name,
  )
  let option_resolution = resolve_compatible_options(
    options.provider_options,
    self.provider_name,
    embedding_reserved_fields(),
  )
  let request_headers = @provider_utils.merge_headers(
    self.request_headers(),
    options.headers,
  )
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.embeddings_url(),
    headers=request_headers,
    body=request_body,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=json => self.error_structure.message(json),
    is_retryable_response=(status_code, error) => {
      self.error_structure.retryable(status_code, error)
    },
    transport=self.http_transport,
  )
  let decoded = decode_embedding_response(
    response.value,
    error_structure=self.error_structure,
  )
  decoded
  .with_diagnostics(
    None,
    None,
    @provider_utils.provider_metadata_from_json(
      response.value,
      self.provider_name,
    ),
    option_resolution.warnings,
  )
  .with_transport(response.request, response.response)
}

///|
/// Versioned V4 boundary for an OpenAI-compatible embedding model.
pub impl @provider.EmbeddingModelV4 for OpenAICompatibleEmbeddingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.EmbeddingModelV4 for OpenAICompatibleEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingModelV4 for OpenAICompatibleEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingModelV4 for OpenAICompatibleEmbeddingModel with fn max_embeddings_per_call(
  self,
) -> Int? {
  Some(self.max_embeddings)
}

///|
pub impl @provider.EmbeddingModelV4 for OpenAICompatibleEmbeddingModel with fn supports_parallel_calls(
  self,
) -> Bool {
  self.supports_parallel
}

///|
pub impl @provider.EmbeddingModelV4 for OpenAICompatibleEmbeddingModel with fn do_embed(
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
