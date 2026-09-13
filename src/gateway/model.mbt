///|
/// AI Gateway provider settings. One API key routes every upstream provider.
pub struct GatewayProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create an AI Gateway provider. The API key defaults to the
/// `AI_GATEWAY_API_KEY` environment variable.
pub fn create_gateway(
  api_key? : String = "",
  base_url? : String = "https://ai-gateway.vercel.sh/v4/ai",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> GatewayProvider {
  {
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Camel-case provider factory matching AI SDK naming.
pub fn createGateway(
  api_key? : String = "",
  base_url? : String = "https://ai-gateway.vercel.sh/v4/ai",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> GatewayProvider {
  create_gateway(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  )
}

///|
fn GatewayProvider::language_model_value(
  self : GatewayProvider,
  model_id : GatewayModelId,
) -> GatewayLanguageModel {
  gateway_chat_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Select a gateway language model for any routed `provider/model` id.
pub fn GatewayProvider::language_model(
  self : GatewayProvider,
  model_id : GatewayModelId,
) -> &@provider.LanguageModelV4 {
  let model = self.language_model_value(model_id)
  model as &@provider.LanguageModelV4
}

///|
/// Alias for `language_model`.
pub fn GatewayProvider::chat(
  self : GatewayProvider,
  model_id : GatewayModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Camel-case alias for `chat`.
pub fn GatewayProvider::chatModel(
  self : GatewayProvider,
  model_id : GatewayModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Camel-case alias for `language_model`.
pub fn GatewayProvider::languageModel(
  self : GatewayProvider,
  model_id : GatewayModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
pub impl @provider.ProviderV4 for GatewayProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for GatewayProvider with fn language_model(
  self,
  model_id,
) {
  GatewayProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for GatewayProvider with fn embedding_model(
  self,
  model_id,
) {
  GatewayProvider::embedding_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for GatewayProvider with fn reranking_model(
  self,
  model_id,
) {
  Some(GatewayProvider::reranking_model(self, model_id))
}

///|
pub impl @provider.ProviderV4 for GatewayProvider with fn image_model(
  _self,
  model_id,
) {
  raise @provider.NoSuchModelError(model_id~, model_type=@provider.ImageModel)
}

///|
pub impl @provider.ProviderV4 for GatewayProvider with fn speech_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for GatewayProvider with fn transcription_model(
  _self,
  _model_id,
) {
  None
}

///|
pub impl @provider.ProviderV4 for GatewayProvider with fn files(_self) {
  None
}

///|
pub impl @provider.ProviderV4 for GatewayProvider with fn skills(_self) {
  None
}

///|
/// Construct the default V4 gateway language model directly.
pub fn gateway(
  model_id : GatewayModelId,
  api_key? : String = "",
  base_url? : String = "https://ai-gateway.vercel.sh/v4/ai",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
) -> &@provider.LanguageModelV4 {
  create_gateway(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
  ).language_model(model_id)
}

///|
/// Select a gateway embedding model.
pub fn GatewayProvider::embedding(
  self : GatewayProvider,
  model_id : String,
) -> &@provider.EmbeddingModelV4 {
  let model = gateway_embedding_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.EmbeddingModelV4
}

///|
/// Alias for `embedding`.
pub fn GatewayProvider::embedding_model(
  self : GatewayProvider,
  model_id : String,
) -> &@provider.EmbeddingModelV4 {
  self.embedding(model_id)
}

///|
/// Camel-case alias for `embedding_model`.
pub fn GatewayProvider::embeddingModel(
  self : GatewayProvider,
  model_id : String,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
/// Select a gateway reranking model.
pub fn GatewayProvider::reranking(
  self : GatewayProvider,
  model_id : String,
) -> &@provider.RerankingModelV4 {
  let model = gateway_reranking_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
  model as &@provider.RerankingModelV4
}

///|
/// Alias for `reranking`.
pub fn GatewayProvider::reranking_model(
  self : GatewayProvider,
  model_id : String,
) -> &@provider.RerankingModelV4 {
  self.reranking(model_id)
}

///|
/// Camel-case alias for `reranking_model`.
pub fn GatewayProvider::rerankingModel(
  self : GatewayProvider,
  model_id : String,
) -> &@provider.RerankingModelV4 {
  self.reranking_model(model_id)
}
