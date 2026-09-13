///|
/// The AI Gateway reranking model: POST /reranking-model with documents +
/// query; the ranking comes back inline.
struct GatewayRerankingModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn gateway_reranking_value(
  model_id : String,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> GatewayRerankingModel {
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
fn GatewayRerankingModel::reranking_headers(
  self : GatewayRerankingModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let resolved = gateway_base_headers(
    api_key=self.api_key,
    headers=self.headers,
    extra~,
    content_type="application/json",
    accept="application/json",
  )
  resolved["ai-reranking-model-specification-version"] = "4"
  resolved["ai-model-id"] = self.model_id
  resolved
}

///|
fn decode_gateway_rerank_response(
  value : Json,
) -> Array[@provider.RerankingModelV4Ranking] raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match value {
    { "ranking": Array(results), .. } => {
      let rankings : Array[@provider.RerankingModelV4Ranking] = []
      for result in results {
        match result {
          {
            "index": Number(index, ..),
            "relevanceScore": Number(score, ..),
            ..
          } =>
            rankings.push(
              @provider.RerankingModelV4Ranking::new(index.to_int(), score),
            )
          _ => fail("gateway rerank response has malformed ranking entries")
        }
      }
      rankings
    }
    _ => fail("gateway rerank response missing ranking")
  }
}

///|
pub impl @provider.RerankingModelV4 for GatewayRerankingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.RerankingModelV4 for GatewayRerankingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.RerankingModelV4 for GatewayRerankingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.RerankingModelV4 for GatewayRerankingModel with fn do_rerank(
  self,
  options,
) {
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
  )
  let documents = match options.documents {
    @provider.TextDocuments(values) =>
      Json::array([ for value in values => Json::string(value) ])
    @provider.ObjectDocuments(values) => Json::array(values)
  }
  let fields : Map[String, Json] = Map([
    ("documents", documents),
    ("query", Json::string(options.query)),
  ])
  if options.top_n is Some(value) {
    fields["topN"] = Json::number(value.to_double())
  }
  if resolution.values.length() > 0 {
    fields["providerOptions"] = Json::object(resolution.values)
  }
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/reranking-model"),
    headers=self.reranking_headers(extra=options.headers),
    body=Json::object(fields),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=gateway_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let rankings = @provider_utils.handle_json_response(
    response, decode_gateway_rerank_response,
  )
  @provider.RerankingModelV4Result::new(
    rankings,
    provider_metadata=@provider_utils.provider_metadata_from_json(
      response.value,
      self.provider_name,
    ),
    warnings=gateway_decode_warnings(
      match response.value {
        Object(fields) => fields.get("warnings")
        _ => None
      },
    ),
    response=response.response,
  )
}
