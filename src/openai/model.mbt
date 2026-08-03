///|
/// Official OpenAI provider. It composes the shared Chat Completions and Open
/// Responses protocol packages instead of duplicating their implementations.
pub struct OpenAIProvider {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv preserve_reasoning : Bool
  priv include_usage : Bool
  priv idle_timeout_ms : Int
}

///|
/// Create an official OpenAI provider factory.
pub fn create_openai(
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  provider_name? : String = "openai",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAIProvider {
  {
    provider_name,
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    preserve_reasoning,
    include_usage,
    idle_timeout_ms,
  }
}

///|
/// AI SDK-style camel-case provider factory.
pub fn createOpenAI(
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  provider_name? : String = "openai",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAIProvider {
  create_openai(
    api_key~,
    base_url~,
    provider_name~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
  )
}

///|
/// Compatibility name for the shared Chat Completions model type.
pub type OpenAICompatibleModel = @openai_compatible.OpenAICompatibleChatModel

///|
/// Compatibility type name for the shared OpenAI embeddings model.
pub type OpenAIEmbeddingModel = @openai_compatible.OpenAICompatibleEmbeddingModel

///|
/// Compatibility type name for the shared legacy completion model.
pub type OpenAICompletionModel = @openai_compatible.OpenAICompatibleCompletionModel

///|
/// Compatibility type name for the shared OpenAI image model.
pub type OpenAIImageModel = @openai_compatible.OpenAICompatibleImageModel

///|
/// Official OpenAI Responses model type.
pub type OpenAIResponsesModel = @open_responses.OpenResponsesLanguageModel

///|
/// Select an official OpenAI Chat Completions model.
pub fn OpenAIProvider::chat(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAICompatibleModel {
  @openai_compatible.create_openai_compatible(
    provider_name=self.provider_name,
    base_url=self.base_url,
    api_key=self.api_key,
    headers=self.headers,
    preserve_reasoning=self.preserve_reasoning,
    include_usage=self.include_usage,
    idle_timeout_ms=self.idle_timeout_ms,
  ).chat_model(model_id)
}

///|
/// Snake-case alias for selecting the Chat Completions model.
pub fn OpenAIProvider::chat_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAICompatibleModel {
  self.chat(model_id)
}

///|
/// Camel-case alias for selecting the Chat Completions model.
pub fn OpenAIProvider::chatModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAICompatibleModel {
  self.chat(model_id)
}

///|
/// Select an official OpenAI text embedding model.
pub fn OpenAIProvider::embedding(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  @openai_compatible.openai_compatible_embedding(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
  )
}

///|
/// Compatibility alias for embedding model selection.
pub fn OpenAIProvider::embedding_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  self.embedding(model_id)
}

///|
/// Camel-case compatibility alias for `embedding_model`.
pub fn OpenAIProvider::embeddingModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  self.embedding(model_id)
}

///|
/// Compatibility alias retained for older AI SDK terminology.
pub fn OpenAIProvider::text_embedding(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  self.embedding(model_id)
}

///|
/// Camel-case compatibility alias for `text_embedding`.
pub fn OpenAIProvider::textEmbedding(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  self.embedding(model_id)
}

///|
/// Compatibility alias retained for older AI SDK terminology.
pub fn OpenAIProvider::text_embedding_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  self.embedding(model_id)
}

///|
/// Camel-case compatibility alias for `text_embedding_model`.
pub fn OpenAIProvider::textEmbeddingModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIEmbeddingModel {
  self.embedding(model_id)
}

///|
/// Select an official OpenAI legacy completion model.
pub fn OpenAIProvider::completion(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAICompletionModel {
  @openai_compatible.openai_compatible_completion(
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
/// Compatibility alias for legacy completion model selection.
pub fn OpenAIProvider::completion_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAICompletionModel {
  self.completion(model_id)
}

///|
/// Camel-case compatibility alias for `completion_model`.
pub fn OpenAIProvider::completionModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAICompletionModel {
  self.completion(model_id)
}

///|
fn openai_image_max_images_per_call(model_id : String) -> Int {
  match model_id {
    "dall-e-3" => 1
    "dall-e-2" => 10
    value if value.has_prefix("gpt-image-") => 10
    "chatgpt-image-latest" => 10
    _ => 1
  }
}

///|
fn openai_image_requires_response_format(model_id : String) -> Bool {
  !model_id.has_prefix("gpt-image-") && !model_id.has_prefix("chatgpt-image-")
}

///|
/// Select an official OpenAI image generation model.
pub fn OpenAIProvider::image(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIImageModel {
  @openai_compatible.openai_compatible_image(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    headers=self.headers,
    max_images_per_call=openai_image_max_images_per_call(model_id),
    include_response_format=openai_image_requires_response_format(model_id),
    idle_timeout_ms=self.idle_timeout_ms,
  )
}

///|
/// Compatibility alias for image model selection.
pub fn OpenAIProvider::image_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIImageModel {
  self.image(model_id)
}

///|
/// Camel-case compatibility alias for `image_model`.
pub fn OpenAIProvider::imageModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIImageModel {
  self.image(model_id)
}

///|
/// Select an official OpenAI Responses API model.
pub fn OpenAIProvider::responses(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesModel {
  @open_responses.create_open_responses(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/responses"),
    api_key=self.api_key,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
  ).responses(model_id)
}

///|
/// Explicit alias for selecting an OpenAI Responses model.
pub fn OpenAIProvider::responses_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesModel {
  self.responses(model_id)
}

///|
/// Camel-case alias for selecting an OpenAI Responses model.
pub fn OpenAIProvider::responsesModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesModel {
  self.responses(model_id)
}

///|
/// Select the default language model. AI SDK 7 uses the Responses API for
/// official OpenAI models.
pub fn OpenAIProvider::language_model(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesModel {
  self.responses(model_id)
}

///|
/// Camel-case compatibility alias for `language_model`.
pub fn OpenAIProvider::languageModel(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAIResponsesModel {
  self.language_model(model_id)
}

///|
/// Construct the default official OpenAI model using the Responses API.
pub fn openai(
  model_id : String,
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
) -> OpenAIResponsesModel {
  create_openai(api_key~, base_url~, headers~, idle_timeout_ms~).responses(
    model_id,
  )
}

///|
/// Construct an official OpenAI Chat Completions model explicitly.
pub fn openai_chat(
  model_id : String,
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompatibleModel {
  create_openai(
    api_key~,
    base_url~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
  ).chat(model_id)
}

///|
/// Construct an official OpenAI text embedding model.
pub fn openai_embedding(
  model_id : String,
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
) -> OpenAIEmbeddingModel {
  create_openai(api_key~, base_url~, headers~, idle_timeout_ms~).embedding(
    model_id,
  )
}

///|
/// Construct an official OpenAI legacy completion model.
pub fn openai_completion(
  model_id : String,
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  headers? : Map[String, String] = Map([]),
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompletionModel {
  create_openai(api_key~, base_url~, headers~, include_usage~, idle_timeout_ms~).completion(
    model_id,
  )
}

///|
/// Construct an official OpenAI image generation model.
pub fn openai_image(
  model_id : String,
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
) -> OpenAIImageModel {
  create_openai(api_key~, base_url~, headers~, idle_timeout_ms~).image(model_id)
}

///|
/// Backward-compatible shortcut for the standalone openai_compatible package.
pub fn openai_compatible(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompatibleModel {
  @openai_compatible.openai_compatible(
    provider_name~,
    base_url~,
    model_id~,
    api_key~,
    headers~,
    preserve_reasoning~,
    include_usage~,
    idle_timeout_ms~,
  )
}
