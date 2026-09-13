///|
/// The Mistral embedding model.
struct MistralEmbeddingModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn mistral_embedding_value(
  model_id : MistralEmbeddingModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> MistralEmbeddingModel {
  {
    provider_name: "mistral.embedding",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn decode_mistral_embedding_response(
  value : Json,
) -> Array[Array[Double]] raise {
  match value {
    { "data": Array(items), .. } => {
      let embeddings : Array[Array[Double]] = []
      for item in items {
        match item {
          { "embedding": Array(values), .. } => {
            let embedding : Array[Double] = []
            for component in values {
              match component {
                Number(value, ..) => embedding.push(value)
                _ => fail("mistral embedding has non-numeric component")
              }
            }
            embeddings.push(embedding)
          }
          _ => fail("mistral embedding response has malformed data items")
        }
      }
      embeddings
    }
    _ => fail("mistral embedding response missing data")
  }
}

///|
pub impl @provider.EmbeddingModelV4 for MistralEmbeddingModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.EmbeddingModelV4 for MistralEmbeddingModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.EmbeddingModelV4 for MistralEmbeddingModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.EmbeddingModelV4 for MistralEmbeddingModel with fn max_embeddings_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
pub impl @provider.EmbeddingModelV4 for MistralEmbeddingModel with fn supports_parallel_calls(
  _self,
) -> Bool {
  true
}

///|
pub impl @provider.EmbeddingModelV4 for MistralEmbeddingModel with fn max_input_bytes_per_call(
  _self,
) -> Int64? {
  None
}

///|
pub impl @provider.EmbeddingModelV4 for MistralEmbeddingModel with fn do_embed(
  self,
  options,
) {
  guard options.values.length() <= 1 else {
    raise @provider.TooManyEmbeddingValuesForCallError(
      provider=self.provider_name,
      model_id=self.model_id,
      max_embeddings_per_call=1,
      values=options.values,
    )
  }
  let fields : Map[String, Json] = Map([
    ("model", Json::string(self.model_id)),
    (
      "input",
      Json::array([ for value in options.values => Json::string(value) ]),
    ),
  ])
  let cancellation_token = options.cancellation_token
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="MISTRAL_API_KEY",
    description="Mistral",
  )
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/embeddings"),
    headers=@provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(
        @provider_utils.merge_headers(
          Map([
            ("Content-Type", "application/json"),
            ("Authorization", "Bearer \{api_key}"),
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
    error_to_message=mistral_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let embeddings = @provider_utils.handle_json_response(
    response, decode_mistral_embedding_response,
  )
  @provider.EmbeddingModelV4Result::new(
    embeddings,
    provider_metadata=@provider_utils.provider_metadata_from_json(
      response.value,
      self.provider_name,
    ),
    request=response.request,
    response=response.response,
  )
}

///|
/// Select a Mistral speech (voxtral tts) model reusing the OpenAI audio wire.
pub fn MistralProvider::speech(
  self : MistralProvider,
  model_id : MistralSpeechModelId,
) -> &@provider.SpeechModelV4 {
  let model = @openai.openai_speech_model(
    provider_name="mistral",
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.SpeechModelV4
}

///|
/// Alias for `speech`.
pub fn MistralProvider::speech_model(
  self : MistralProvider,
  model_id : MistralSpeechModelId,
) -> &@provider.SpeechModelV4 {
  self.speech(model_id)
}

///|
/// Camel-case alias for `speech_model`.
pub fn MistralProvider::speechModel(
  self : MistralProvider,
  model_id : MistralSpeechModelId,
) -> &@provider.SpeechModelV4 {
  self.speech_model(model_id)
}

///|
/// Select a Mistral transcription (voxtral) model reusing the OpenAI audio
/// wire. Streaming uses the native WebSocket connector.
pub fn MistralProvider::transcription(
  self : MistralProvider,
  model_id : MistralTranscriptionModelId,
) -> &@provider.TranscriptionModelV4 {
  let model = @openai.openai_transcription_model(
    provider_name="mistral",
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
    websocket_connector=@provider_utils.native_websocket_connector(),
  )
  model as &@provider.TranscriptionModelV4
}

///|
/// Alias for `transcription`.
pub fn MistralProvider::transcription_model(
  self : MistralProvider,
  model_id : MistralTranscriptionModelId,
) -> &@provider.TranscriptionModelV4 {
  self.transcription(model_id)
}

///|
/// Camel-case alias for `transcription_model`.
pub fn MistralProvider::transcriptionModel(
  self : MistralProvider,
  model_id : MistralTranscriptionModelId,
) -> &@provider.TranscriptionModelV4 {
  self.transcription_model(model_id)
}
