///|
/// The Google embedding model (models/{model}:embedContent).
struct GoogleEmbeddingModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
/// Google's per-request embedding input limit.
pub const GOOGLE_MAX_EMBEDDINGS_PER_CALL : Int = 100

///|
fn google_embedding_value(
  model_id : GoogleEmbeddingModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> GoogleEmbeddingModel {
  {
    provider_name: "google.textEmbedding",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn decode_google_embedding_response(
  value : Json,
) -> (Array[Array[Double]], Int?) raise {
  match value {
    { "embedding": { "values": Array(components), .. }, .. } => {
      let embedding : Array[Double] = []
      for component in components {
        match component {
          Number(number, ..) => embedding.push(number)
          _ => fail("google embedding has non-numeric component")
        }
      }
      let mut tokens : Int? = None
      match value {
        {
          "usageMetadata": { "totalBillableCharacters": Number(count, ..), .. },
          ..
        } => tokens = Some(count.to_int())
        _ => ()
      }
      ([embedding], tokens)
    }
    _ => fail("google embedding response missing embedding")
  }
}

///|
pub impl @provider.EmbeddingModelV4 for GoogleEmbeddingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.EmbeddingModelV4 for GoogleEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingModelV4 for GoogleEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingModelV4 for GoogleEmbeddingModel with fn max_embeddings_per_call(
  _self,
) -> Int? {
  Some(GOOGLE_MAX_EMBEDDINGS_PER_CALL)
}

///|
pub impl @provider.EmbeddingModelV4 for GoogleEmbeddingModel with fn supports_parallel_calls(
  _self,
) -> Bool {
  true
}

///|
pub impl @provider.EmbeddingModelV4 for GoogleEmbeddingModel with fn max_input_bytes_per_call(
  _self,
) -> Int64? {
  None
}

///|
pub impl @provider.EmbeddingModelV4 for GoogleEmbeddingModel with fn do_embed(
  self,
  options,
) {
  guard options.values.length() <= GOOGLE_MAX_EMBEDDINGS_PER_CALL else {
    raise @provider.TooManyEmbeddingValuesForCallError(
      provider=self.provider_name,
      model_id=self.model_id,
      max_embeddings_per_call=GOOGLE_MAX_EMBEDDINGS_PER_CALL,
      values=options.values,
    )
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["google"],
  )
  let fields : Map[String, Json] = Map([
    (
      "content",
      Json::object({
        "parts": Json::array(
          [
            for value in options.values => { "text": value }
          ],
        ),
      }),
    ),
  ])
  if resolution.values.get("outputDimensionality") is Some(value) {
    fields["outputDimensionality"] = value
  }
  if resolution.values.get("taskType") is Some(value) {
    fields["taskType"] = value
  }
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url="\{self.base_url}/\{get_model_path(self.model_id)}:embedContent",
    headers=@provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(
        @provider_utils.merge_headers(
          Map([
            (
              "x-goog-api-key",
              @provider_utils.load_api_key(
                self.api_key,
                environment_variable_name="GOOGLE_GENERATIVE_AI_API_KEY",
                description="Google Gemini",
              ),
            ),
            ("Content-Type", "application/json"),
          ]),
          self.headers,
        ),
        options.headers,
      ),
      ["ai-sdk/\{self.provider_name}/\{VERSION}"],
    ),
    body=Json::object(fields),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=google_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (embeddings, tokens) = @provider_utils.handle_json_response(
    response, decode_google_embedding_response,
  )
  @provider.EmbeddingModelV4Result::new(
    embeddings,
    usage?=tokens.map(@provider.EmbeddingModelV4Usage::new),
    request=response.request,
    response=response.response,
  )
}
