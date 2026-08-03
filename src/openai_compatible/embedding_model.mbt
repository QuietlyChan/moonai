///|
/// A text embedding model using the OpenAI embeddings wire protocol.
pub struct OpenAICompatibleEmbeddingModel {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv model_id : String
  priv headers : Map[String, String]
  priv max_embeddings : Int
  priv idle_timeout_ms : Int
}

///|
/// Construct an OpenAI-compatible embedding model directly.
pub fn openai_compatible_embedding(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  max_embeddings_per_call? : Int = 2048,
) -> OpenAICompatibleEmbeddingModel {
  {
    provider_name: "\{provider_name}.embedding",
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
    headers: @provider_utils.copy_headers(headers),
    max_embeddings: max_embeddings_per_call,
    idle_timeout_ms,
  }
}

///|
fn OpenAICompatibleEmbeddingModel::embeddings_url(
  self : OpenAICompatibleEmbeddingModel,
) -> String {
  @provider_utils.append_path(self.base_url, "/embeddings")
}

///|
fn OpenAICompatibleEmbeddingModel::request_headers(
  self : OpenAICompatibleEmbeddingModel,
) -> Map[String, String] {
  let headers = @provider_utils.copy_headers(self.headers)
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  if self.api_key != "" {
    headers["Authorization"] = "Bearer \{self.api_key}"
  }
  headers
}

///|
pub impl @moonai.EmbeddingModel for OpenAICompatibleEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @moonai.EmbeddingModel for OpenAICompatibleEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @moonai.EmbeddingModel for OpenAICompatibleEmbeddingModel with fn max_embeddings_per_call(
  self,
) -> Int {
  self.max_embeddings
}

///|
pub impl @moonai.EmbeddingModel for OpenAICompatibleEmbeddingModel with fn embed(
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
  options : @moonai.EmbeddingOptions,
) -> @moonai.EmbeddingBatchResponse {
  let request_body = encode_embedding_request(self.model_id, values, options)
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
  )
  let decoded = decode_embedding_response(response.value)
  decoded
  .with_diagnostics(
    None,
    None,
    @provider_utils.provider_metadata_from_json(
      response.value,
      self.provider_name,
    ),
    [],
  )
  .with_transport(response.request, response.response)
}
