///|
/// The Cohere embedding model (/embed with float vectors).
struct CohereEmbeddingModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
/// Cohere's per-request embedding input limit.
pub const COHERE_MAX_EMBEDDINGS_PER_CALL : Int = 96

///|
fn cohere_embedding_value(
  model_id : CohereEmbeddingModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> CohereEmbeddingModel {
  {
    provider_name: "cohere.textEmbedding",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn decode_cohere_embedding_response(
  value : Json,
) -> (Array[Array[Double]], Int?) raise {
  match value {
    { "embeddings": { "float": Array(rows), .. }, .. } => {
      let embeddings : Array[Array[Double]] = []
      for row in rows {
        match row {
          Array(components) => {
            let embedding : Array[Double] = []
            for component in components {
              match component {
                Number(value, ..) => embedding.push(value)
                _ => fail("cohere embedding has non-numeric component")
              }
            }
            embeddings.push(embedding)
          }
          _ => fail("cohere embedding response has malformed rows")
        }
      }
      let mut tokens : Int? = None
      match value {
        {
          "meta": {
            "billed_units": { "input_tokens": Number(count, ..), .. },
            ..
          },
          ..
        } => tokens = Some(count.to_int())
        _ => ()
      }
      (embeddings, tokens)
    }
    _ => fail("cohere embedding response missing embeddings")
  }
}

///|
pub impl @provider.EmbeddingModelV4 for CohereEmbeddingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.EmbeddingModelV4 for CohereEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingModelV4 for CohereEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingModelV4 for CohereEmbeddingModel with fn max_embeddings_per_call(
  _self,
) -> Int? {
  Some(COHERE_MAX_EMBEDDINGS_PER_CALL)
}

///|
pub impl @provider.EmbeddingModelV4 for CohereEmbeddingModel with fn supports_parallel_calls(
  _self,
) -> Bool {
  true
}

///|
pub impl @provider.EmbeddingModelV4 for CohereEmbeddingModel with fn max_input_bytes_per_call(
  _self,
) -> Int64? {
  None
}

///|
pub impl @provider.EmbeddingModelV4 for CohereEmbeddingModel with fn do_embed(
  self,
  options,
) {
  guard options.values.length() <= COHERE_MAX_EMBEDDINGS_PER_CALL else {
    raise @provider.TooManyEmbeddingValuesForCallError(
      provider=self.provider_name,
      model_id=self.model_id,
      max_embeddings_per_call=COHERE_MAX_EMBEDDINGS_PER_CALL,
      values=options.values,
    )
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["cohere"],
  )
  let fields : Map[String, Json] = Map([
    ("model", Json::string(self.model_id)),
    ("embedding_types", Json::array([Json::string("float")])),
    (
      "texts",
      Json::array([ for value in options.values => Json::string(value) ]),
    ),
    (
      "input_type",
      Json::string(
        match resolution.values.get("inputType") {
          Some(String(value)) => value
          _ => "search_query"
        },
      ),
    ),
  ])
  if resolution.values.get("truncate") is Some(value) {
    fields["truncate"] = value
  }
  if resolution.values.get("outputDimension") is Some(value) {
    fields["output_dimension"] = value
  }
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/embed"),
    headers=cohere_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
    ),
    body=Json::object(fields),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=cohere_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (embeddings, tokens) = @provider_utils.handle_json_response(
    response, decode_cohere_embedding_response,
  )
  @provider.EmbeddingModelV4Result::new(
    embeddings,
    usage?=tokens.map(@provider.EmbeddingModelV4Usage::new),
    request=response.request,
    response=response.response,
  )
}

///|
/// The Cohere reranking model (/rerank).
struct CohereRerankingModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn cohere_reranking_value(
  model_id : CohereRerankingModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> CohereRerankingModel {
  {
    provider_name: "cohere.reranking",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn decode_cohere_rerank_response(
  value : Json,
) -> Array[@provider.RerankingModelV4Ranking] raise {
  match value {
    { "results": Array(results), .. } => {
      let rankings : Array[@provider.RerankingModelV4Ranking] = []
      for result in results {
        match result {
          {
            "index": Number(index, ..),
            "relevance_score": Number(score, ..),
            ..
          } =>
            rankings.push(
              @provider.RerankingModelV4Ranking::new(index.to_int(), score),
            )
          _ => fail("cohere rerank response has malformed results")
        }
      }
      rankings
    }
    _ => fail("cohere rerank response missing results")
  }
}

///|
pub impl @provider.RerankingModelV4 for CohereRerankingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.RerankingModelV4 for CohereRerankingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.RerankingModelV4 for CohereRerankingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.RerankingModelV4 for CohereRerankingModel with fn do_rerank(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  if options.documents is @provider.ObjectDocuments(_) {
    warnings.push(
      @provider.Warning::Compatibility(
        feature="object documents",
        details="Object documents are converted to strings.",
      ),
    )
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["cohere"],
  )
  let documents = match options.documents {
    @provider.TextDocuments(values) =>
      Json::array([ for value in values => Json::string(value) ])
    @provider.ObjectDocuments(values) =>
      Json::array([ for value in values => Json::string(value.stringify()) ])
  }
  let fields : Map[String, Json] = Map([
    ("model", Json::string(self.model_id)),
    ("query", Json::string(options.query)),
    ("documents", documents),
  ])
  if options.top_n is Some(value) {
    fields["top_n"] = Json::number(value.to_double())
  }
  if resolution.values.get("maxTokensPerDoc") is Some(value) {
    fields["max_tokens_per_doc"] = value
  }
  if resolution.values.get("priority") is Some(value) {
    fields["priority"] = value
  }
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/rerank"),
    headers=cohere_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
    ),
    body=Json::object(fields),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=cohere_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let rankings = @provider_utils.handle_json_response(
    response, decode_cohere_rerank_response,
  )
  @provider.RerankingModelV4Result::new(
    rankings,
    response={ ..response.response, body: Some(response.value.stringify()), },
    warnings~,
  )
}
