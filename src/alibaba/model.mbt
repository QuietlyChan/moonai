///|
/// Alibaba Cloud (DashScope/Qwen) provider settings.
pub struct AlibabaProvider {
  priv api_key : String
  priv base_url : String
  priv embedding_base_url : String
  priv video_base_url : String
  priv headers : Map[String, String]
  priv include_usage : Bool
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
fn load_alibaba_api_key(
  api_key : String,
) -> String raise @provider.LoadAPIKeyError {
  @provider_utils.load_api_key(
    api_key,
    environment_variable_name="ALIBABA_API_KEY",
    description="Alibaba",
  )
}

///|
/// Create an Alibaba Cloud provider.
pub fn create_alibaba(
  api_key? : String = "",
  base_url? : String = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
  embedding_base_url? : String = "https://dashscope-intl.aliyuncs.com/api/v1",
  video_base_url? : String = "https://dashscope-intl.aliyuncs.com",
  headers? : Map[String, String] = Map([]),
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> AlibabaProvider {
  {
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    embedding_base_url: @provider_utils.without_trailing_slash(
      embedding_base_url,
    ),
    video_base_url: @provider_utils.without_trailing_slash(video_base_url),
    headers: @provider_utils.copy_headers(headers),
    include_usage,
    idle_timeout_ms,
    id_generator: id_generator.unwrap_or(@provider_utils.generate_id),
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// Camel-case provider factory matching AI SDK naming.
pub fn createAlibaba(
  api_key? : String = "",
  base_url? : String = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
  embedding_base_url? : String = "https://dashscope-intl.aliyuncs.com/api/v1",
  video_base_url? : String = "https://dashscope-intl.aliyuncs.com",
  headers? : Map[String, String] = Map([]),
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> AlibabaProvider {
  create_alibaba(
    api_key~,
    base_url~,
    embedding_base_url~,
    video_base_url~,
    headers~,
    include_usage~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
/// Construct the concrete chat model behind the public V4 boundary.
fn AlibabaProvider::language_model_value(
  self : AlibabaProvider,
  model_id : AlibabaChatModelId,
) -> AlibabaChatModel {
  alibaba_chat_value(
    model_id,
    api_key=self.api_key,
    base_url=self.base_url,
    headers=self.headers,
    include_usage=self.include_usage,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
    id_generator=self.id_generator,
  )
}

///|
/// Alias for `chat` used by provider-neutral model factories.
pub fn AlibabaProvider::language_model(
  self : AlibabaProvider,
  model_id : AlibabaChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Select an Alibaba Chat Completions language model.
pub fn AlibabaProvider::chat(
  self : AlibabaProvider,
  model_id : AlibabaChatModelId,
) -> &@provider.LanguageModelV4 {
  let model = self.language_model_value(model_id)
  model as &@provider.LanguageModelV4
}

///|
/// Camel-case alias for `language_model`.
pub fn AlibabaProvider::languageModel(
  self : AlibabaProvider,
  model_id : AlibabaChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Camel-case alias for `chat`.
pub fn AlibabaProvider::chatModel(
  self : AlibabaProvider,
  model_id : AlibabaChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat(model_id)
}

///|
/// Construct the concrete embedding model behind the public V4 boundary.
fn AlibabaProvider::embedding_model_value(
  self : AlibabaProvider,
  model_id : AlibabaEmbeddingModelId,
) -> AlibabaEmbeddingModel {
  alibaba_embedding_value(
    model_id,
    api_key=self.api_key,
    base_url=self.embedding_base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Select a native Alibaba text embedding model.
pub fn AlibabaProvider::embedding(
  self : AlibabaProvider,
  model_id : AlibabaEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  let model = self.embedding_model_value(model_id)
  model as &@provider.EmbeddingModelV4
}

///|
/// Alias for `embedding`.
pub fn AlibabaProvider::embedding_model(
  self : AlibabaProvider,
  model_id : AlibabaEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding(model_id)
}

///|
/// Camel-case alias for `embedding_model`.
pub fn AlibabaProvider::embeddingModel(
  self : AlibabaProvider,
  model_id : AlibabaEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
/// Construct the concrete video model behind the public V4 boundary.
fn AlibabaProvider::video_model_value(
  self : AlibabaProvider,
  model_id : AlibabaVideoModelId,
) -> AlibabaVideoModel {
  alibaba_video_value(
    model_id,
    api_key=self.api_key,
    base_url=self.video_base_url,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Select an Alibaba asynchronous video generation model.
pub fn AlibabaProvider::video(
  self : AlibabaProvider,
  model_id : AlibabaVideoModelId,
) -> &@provider.VideoModelV4 {
  let model = self.video_model_value(model_id)
  model as &@provider.VideoModelV4
}

///|
/// Camel-case alias for `video`.
pub fn AlibabaProvider::videoModel(
  self : AlibabaProvider,
  model_id : AlibabaVideoModelId,
) -> &@provider.VideoModelV4 {
  self.video(model_id)
}

///|
/// Construct the default V4 Alibaba language model directly.
pub fn alibaba(
  model_id : AlibabaChatModelId,
  api_key? : String = "",
  base_url? : String = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
  headers? : Map[String, String] = Map([]),
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_alibaba(
    api_key~,
    base_url~,
    headers~,
    include_usage~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}
