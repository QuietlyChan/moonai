///|
/// Configuration shared by models served by one OpenAI-compatible endpoint.
pub struct OpenAICompatibleProvider {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv preserve_reasoning : Bool
  priv include_usage : Bool
  priv max_embeddings_per_call : Int
  priv idle_timeout_ms : Int
}

///|
/// Create an OpenAI-compatible provider factory.
pub fn create_openai_compatible(
  provider_name~ : String,
  base_url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  max_embeddings_per_call? : Int = 2048,
) -> OpenAICompatibleProvider {
  {
    provider_name,
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    preserve_reasoning,
    include_usage,
    max_embeddings_per_call,
    idle_timeout_ms,
  }
}

///|
/// AI SDK-style camel-case provider factory.
pub fn createOpenAICompatible(
  provider_name~ : String,
  base_url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  max_embeddings_per_call? : Int = 2048,
) -> OpenAICompatibleProvider {
  create_openai_compatible(
    provider_name~,
    base_url~,
    api_key~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
    max_embeddings_per_call~,
  )
}

///|
/// Select a Chat Completions model.
pub fn OpenAICompatibleProvider::chat_model(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleChatModel {
  {
    provider_name: "\{self.provider_name}.chat",
    api_key: self.api_key,
    base_url: self.base_url,
    model_id,
    headers: @provider_utils.copy_headers(self.headers),
    preserve_reasoning: self.preserve_reasoning,
    include_usage: self.include_usage,
    idle_timeout_ms: self.idle_timeout_ms,
  }
}

///|
/// Select the default language model, which is a chat model for this package.
pub fn OpenAICompatibleProvider::language_model(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleChatModel {
  self.chat_model(model_id)
}

///|
/// Camel-case compatibility alias for `language_model`.
pub fn OpenAICompatibleProvider::languageModel(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleChatModel {
  self.language_model(model_id)
}

///|
/// Short alias for `chat_model`.
pub fn OpenAICompatibleProvider::chat(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleChatModel {
  self.chat_model(model_id)
}

///|
/// Camel-case compatibility alias for `chat_model`.
pub fn OpenAICompatibleProvider::chatModel(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleChatModel {
  self.chat_model(model_id)
}

///|
/// Select a text embedding model.
pub fn OpenAICompatibleProvider::embedding_model(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleEmbeddingModel {
  openai_compatible_embedding(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    max_embeddings_per_call=self.max_embeddings_per_call,
    idle_timeout_ms=self.idle_timeout_ms,
  )
}

///|
/// Camel-case compatibility alias for `embedding_model`.
pub fn OpenAICompatibleProvider::embeddingModel(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleEmbeddingModel {
  self.embedding_model(model_id)
}

///|
/// Short embedding alias matching the OpenAI provider API.
pub fn OpenAICompatibleProvider::embedding(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleEmbeddingModel {
  self.embedding_model(model_id)
}

///|
/// Compatibility alias for text embedding model selection.
pub fn OpenAICompatibleProvider::text_embedding_model(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleEmbeddingModel {
  self.embedding_model(model_id)
}

///|
/// Snake-case short alias for text embedding model selection.
pub fn OpenAICompatibleProvider::text_embedding(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleEmbeddingModel {
  self.embedding_model(model_id)
}

///|
/// Camel-case compatibility alias for `text_embedding_model`.
pub fn OpenAICompatibleProvider::textEmbeddingModel(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleEmbeddingModel {
  self.embedding_model(model_id)
}

///|
/// Select a legacy text completion model.
pub fn OpenAICompatibleProvider::completion_model(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleCompletionModel {
  openai_compatible_completion(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    include_usage=self.include_usage,
    idle_timeout_ms=self.idle_timeout_ms,
  )
}

///|
/// Camel-case compatibility alias for `completion_model`.
pub fn OpenAICompatibleProvider::completionModel(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleCompletionModel {
  self.completion_model(model_id)
}

///|
/// Short alias for legacy completion model selection.
pub fn OpenAICompatibleProvider::completion(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleCompletionModel {
  self.completion_model(model_id)
}

///|
/// Select an image generation model.
pub fn OpenAICompatibleProvider::image_model(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleImageModel {
  openai_compatible_image(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
  )
}

///|
/// Camel-case compatibility alias for `image_model`.
pub fn OpenAICompatibleProvider::imageModel(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleImageModel {
  self.image_model(model_id)
}

///|
/// Short alias for image model selection.
pub fn OpenAICompatibleProvider::image(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleImageModel {
  self.image_model(model_id)
}

///|
/// A chat model using the OpenAI Chat Completions wire protocol.
pub struct OpenAICompatibleChatModel {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv model_id : String
  priv headers : Map[String, String]
  priv preserve_reasoning : Bool
  priv include_usage : Bool
  priv idle_timeout_ms : Int
}

///|
/// Compatibility type name used by the first moonai release.
pub type OpenAICompatibleModel = OpenAICompatibleChatModel

///|
/// Construct an OpenAI-compatible chat model directly.
pub fn openai_compatible(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompatibleChatModel {
  create_openai_compatible(
    provider_name~,
    base_url~,
    api_key~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
  ).chat_model(model_id)
}

///|
fn OpenAICompatibleChatModel::chat_completions_url(
  self : OpenAICompatibleChatModel,
) -> String {
  @provider_utils.append_path(self.base_url, "/chat/completions")
}

///|
fn OpenAICompatibleChatModel::request_headers(
  self : OpenAICompatibleChatModel,
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
pub impl @moonai.ChatModel for OpenAICompatibleChatModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @moonai.ChatModel for OpenAICompatibleChatModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @moonai.ChatModel for OpenAICompatibleChatModel with fn generate(
  self,
  options,
) {
  self.generate_chat(options)
}

///|
pub impl @moonai.ChatModel for OpenAICompatibleChatModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_chat(options, on_event)
}
