///|
/// The concrete TogetherAI reranking model behind the public V4 boundary.
struct TogetherAIRerankingModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn togetherai_reranking_value(
  model_id : TogetherAIRerankingModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> TogetherAIRerankingModel {
  {
    provider_name: "togetherai.reranking",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn decode_togetherai_rerank_response(
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
          _ => fail("togetherai rerank response has malformed results")
        }
      }
      rankings
    }
    _ => fail("togetherai rerank response missing results")
  }
}

///|
pub impl @provider.RerankingModelV4 for TogetherAIRerankingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.RerankingModelV4 for TogetherAIRerankingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.RerankingModelV4 for TogetherAIRerankingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.RerankingModelV4 for TogetherAIRerankingModel with fn do_rerank(
  self,
  options,
) {
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["togetherai"],
  )
  let documents = match options.documents {
    @provider.TextDocuments(values) =>
      Json::array([ for value in values => Json::string(value) ])
    @provider.ObjectDocuments(values) => Json::array(values)
  }
  let fields : Map[String, Json] = Map([
    ("model", Json::string(self.model_id)),
    ("documents", documents),
    ("query", Json::string(options.query)),
    ("return_documents", Json::boolean(false)),
  ])
  if options.top_n is Some(value) {
    fields["top_n"] = Json::number(value.to_double())
  }
  if resolution.values.get("rankFields") is Some(value) {
    fields["rank_fields"] = value
  }
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/rerank"),
    headers=@provider_utils.merge_headers(
      togetherai_request_headers(
        provider_name=self.provider_name,
        api_key=self.api_key,
        headers=self.headers,
      ),
      options.headers,
    ),
    body=Json::object(fields),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=togetherai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let rankings = @provider_utils.handle_json_response(
    response, decode_togetherai_rerank_response,
  )
  @provider.RerankingModelV4Result::new(rankings, response={
    ..response.response,
    id: json_string_field(response.value, "id"),
    model_id: json_string_field(response.value, "model"),
    body: Some(response.value.stringify()),
  })
}

///|
fn json_string_field(value : Json, key : String) -> String? {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(String(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}
