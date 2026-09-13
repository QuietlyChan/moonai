///|
/// Baseten provider settings.
pub struct BasetenProvider {
  priv api_key : String
  priv base_url : String
  priv model_url : String?
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create a Baseten provider. The API key defaults to the `BASETEN_API_KEY`
/// environment variable. `model_url` addresses a dedicated deployment for
/// chat (`/sync/v1`) or embeddings (`/sync` or `/sync/v1`); without it the
/// Model APIs are used for chat.
pub fn create_baseten(
  api_key? : String = "",
  base_url? : String = "https://inference.baseten.co/v1",
  model_url? : String,
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> BasetenProvider {
  {
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_url: model_url.map(@provider_utils.without_trailing_slash),
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    id_generator: id_generator.unwrap_or(@provider_utils.generate_id),
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Camel-case provider factory matching AI SDK naming.
pub fn createBaseten(
  api_key? : String = "",
  base_url? : String = "https://inference.baseten.co/v1",
  model_url? : String,
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> BasetenProvider {
  create_baseten(
    api_key~,
    base_url~,
    model_url?,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
fn BasetenProvider::chat_base_url(self : BasetenProvider) -> String raise {
  match self.model_url {
    Some(url) =>
      if url.contains("/sync/v1") {
        url
      } else if url.contains("/predict") {
        fail("Not supported. You must use a /sync/v1 endpoint for chat models.")
      } else {
        self.base_url
      }
    None => self.base_url
  }
}

///|
/// Select a Baseten chat model. Dedicated deployments need no model id.
pub fn BasetenProvider::chat(
  self : BasetenProvider,
  model_id? : BasetenChatModelId,
) -> &@provider.LanguageModelV4 raise {
  let resolved_id = model_id.unwrap_or(
    if self.model_url is Some(_) {
      "placeholder"
    } else {
      "chat"
    },
  )
  let model = @openai_compatible.OpenAICompatibleChatLanguageModel::new(
    resolved_id,
    @openai_compatible.OpenAICompatibleChatConfig::new(
      provider_name="baseten.chat",
      base_url=self.chat_base_url(),
      api_key=self.api_key,
      api_key_environment_variable="BASETEN_API_KEY",
      headers=self.headers,
      include_usage=true,
      supports_structured_outputs=true,
      error_structure=baseten_error_structure(),
      idle_timeout_ms=self.idle_timeout_ms,
      http_transport=self.http_transport,
      id_generator=self.id_generator,
    ),
  )
  model as &@provider.LanguageModelV4
}

///|
/// Alias for `chat` used by provider-neutral model factories.
pub fn BasetenProvider::language_model(
  self : BasetenProvider,
  model_id? : BasetenChatModelId,
) -> &@provider.LanguageModelV4 raise {
  self.chat(model_id?)
}

///|
/// Camel-case alias for `chat`.
pub fn BasetenProvider::chatModel(
  self : BasetenProvider,
  model_id? : BasetenChatModelId,
) -> &@provider.LanguageModelV4 raise {
  self.chat(model_id?)
}

///|
/// Camel-case alias for `language_model`.
pub fn BasetenProvider::languageModel(
  self : BasetenProvider,
  model_id? : BasetenChatModelId,
) -> &@provider.LanguageModelV4 raise {
  self.language_model(model_id?)
}

///|
/// Select a Baseten embedding model against a dedicated `/sync` deployment.
pub fn BasetenProvider::embedding(
  self : BasetenProvider,
  model_id? : BasetenEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 raise {
  let model_url = match self.model_url {
    Some(url) => url
    None =>
      fail(
        "No model URL provided for embeddings. Please set model_url option for embeddings.",
      )
  }
  guard model_url.contains("/sync") else {
    fail(
      "Not supported. You must use a /sync or /sync/v1 endpoint for embeddings.",
    )
  }
  // /sync URLs without /v1 need the version segment appended for the
  // OpenAI-compatible embeddings path.
  let base_url = if model_url.contains("/sync") &&
    !model_url.contains("/sync/v1") {
    "\{model_url}/v1"
  } else {
    model_url
  }
  let model = @openai_compatible.openai_compatible_embedding(
    provider_name="baseten",
    base_url~,
    model_id=model_id.unwrap_or("embeddings"),
    api_key=self.api_key,
    headers=self.headers,
    error_structure=baseten_error_structure(),
    max_embeddings_per_call=MAX_EMBEDDINGS_PER_CALL,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
    api_key_environment_variable="BASETEN_API_KEY",
  )
  model as &@provider.EmbeddingModelV4
}

///|
/// Alias for `embedding`.
pub fn BasetenProvider::embedding_model(
  self : BasetenProvider,
  model_id? : BasetenEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 raise {
  self.embedding(model_id?)
}

///|
/// Camel-case alias for `embedding_model`.
pub fn BasetenProvider::embeddingModel(
  self : BasetenProvider,
  model_id? : BasetenEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 raise {
  self.embedding_model(model_id?)
}

///|
pub impl @provider.ProviderV4 for BasetenProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for BasetenProvider with fn language_model(
  self,
  model_id,
) {
  BasetenProvider::language_model(self, model_id~)
}

///|
pub impl @provider.ProviderV4 for BasetenProvider with fn embedding_model(
  self,
  model_id,
) {
  BasetenProvider::embedding_model(self, model_id~)
}

///|
pub impl @provider.ProviderV4 for BasetenProvider with fn reranking_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for BasetenProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for BasetenProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for BasetenProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for BasetenProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for BasetenProvider with fn skills(_self) {
  None
}
