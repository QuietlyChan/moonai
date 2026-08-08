///|
/// Configuration shared by models served by one OpenAI-compatible endpoint.
pub struct OpenAICompatibleProvider {
  priv provider_name : String
  priv api_key : String
  priv api_key_environment_variable : String?
  priv base_url : String
  priv headers : Map[String, String]
  priv query_params : Map[String, String]
  priv include_usage : Bool
  priv supports_structured_outputs : Bool
  priv supports_top_k : Bool
  priv supports_frequency_penalty : Bool
  priv supported_url_rules : Array[@provider.SupportedUrlRule]
  priv transform_request_body : (Json) -> Json
  priv error_structure : OpenAICompatibleErrorStructure
  priv metadata_extractor : OpenAICompatibleMetadataExtractor?
  priv convert_usage : OpenAICompatibleUsageConverter
  priv max_embeddings_per_call : Int
  priv supports_parallel_calls : Bool
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
  priv custom_http_transport : &@provider_utils.HttpTransport?
  priv prompt_converter : OpenAICompatibleV4PromptConverter
  priv transform_options : OpenAICompatibleV4OptionsTransformer
}

///|
fn openai_compatible_user_agent_suffix(provider_name : String) -> String {
  if provider_name.has_prefix("alibaba") {
    "moonai/alibaba/\{VERSION}"
  } else {
    "moonai/openai-compatible/\{VERSION}"
  }
}

///|
/// Create an OpenAI-compatible provider factory.
pub fn create_openai_compatible(
  provider_name~ : String,
  base_url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  query_params? : Map[String, String] = Map([]),
  include_usage? : Bool = false,
  supports_structured_outputs? : Bool = false,
  transform_request_body? : (Json) -> Json = value => value,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  metadata_extractor? : OpenAICompatibleMetadataExtractor,
  convert_usage? : OpenAICompatibleUsageConverter = convert_openai_compatible_chat_usage,
  idle_timeout_ms? : Int = 120_000,
  max_embeddings_per_call? : Int = 2048,
  supports_parallel_calls? : Bool = true,
  supports_top_k? : Bool = false,
  supports_frequency_penalty? : Bool = true,
  supported_urls? : Array[@provider.SupportedUrlRule] = [],
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
  prompt_converter? : OpenAICompatibleV4PromptConverter = default_openai_compatible_v4_prompt_converter,
  transform_options? : OpenAICompatibleV4OptionsTransformer = identity_compatible_v4_options,
) -> OpenAICompatibleProvider {
  {
    provider_name,
    api_key,
    api_key_environment_variable,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    query_params: @provider_utils.copy_headers(query_params),
    include_usage,
    supports_structured_outputs,
    supports_top_k,
    supports_frequency_penalty,
    supported_url_rules: supported_urls.copy(),
    transform_request_body,
    error_structure,
    metadata_extractor,
    convert_usage,
    max_embeddings_per_call,
    supports_parallel_calls,
    idle_timeout_ms,
    id_generator: id_generator.unwrap_or(@provider_utils.generate_id),
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
    custom_http_transport: http_transport,
    prompt_converter,
    transform_options,
  }
}

///|
/// AI SDK-style camel-case provider factory.
pub fn createOpenAICompatible(
  provider_name~ : String,
  base_url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  query_params? : Map[String, String] = Map([]),
  include_usage? : Bool = false,
  supports_structured_outputs? : Bool = false,
  transform_request_body? : (Json) -> Json = value => value,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  metadata_extractor? : OpenAICompatibleMetadataExtractor,
  convert_usage? : OpenAICompatibleUsageConverter = convert_openai_compatible_chat_usage,
  idle_timeout_ms? : Int = 120_000,
  max_embeddings_per_call? : Int = 2048,
  supports_parallel_calls? : Bool = true,
  supports_top_k? : Bool = false,
  supports_frequency_penalty? : Bool = true,
  supported_urls? : Array[@provider.SupportedUrlRule] = [],
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
  prompt_converter? : OpenAICompatibleV4PromptConverter = default_openai_compatible_v4_prompt_converter,
  transform_options? : OpenAICompatibleV4OptionsTransformer = identity_compatible_v4_options,
) -> OpenAICompatibleProvider {
  create_openai_compatible(
    provider_name~,
    base_url~,
    api_key~,
    headers~,
    query_params~,
    include_usage~,
    supports_structured_outputs~,
    transform_request_body~,
    error_structure~,
    metadata_extractor?,
    convert_usage~,
    idle_timeout_ms~,
    max_embeddings_per_call~,
    supports_parallel_calls~,
    supports_top_k~,
    supports_frequency_penalty~,
    supported_urls~,
    http_transport?,
    api_key_environment_variable?,
    id_generator?,
    prompt_converter~,
    transform_options~,
  )
}

///|
fn OpenAICompatibleProvider::chat_language_model(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
) -> OpenAICompatibleChatLanguageModel {
  OpenAICompatibleChatLanguageModel::new(
    model_id,
    OpenAICompatibleChatConfig::new(
      provider_name="\{self.provider_name}.chat",
      base_url=self.base_url,
      api_key=self.api_key,
      api_key_environment_variable?=self.api_key_environment_variable,
      headers=self.headers,
      query_params=self.query_params,
      include_usage=self.include_usage,
      supports_structured_outputs=self.supports_structured_outputs,
      supports_top_k=self.supports_top_k,
      supports_frequency_penalty=self.supports_frequency_penalty,
      supported_urls=self.supported_url_rules,
      transform_request_body=self.transform_request_body,
      error_structure=self.error_structure,
      metadata_extractor?=self.metadata_extractor,
      convert_usage=self.convert_usage,
      idle_timeout_ms=self.idle_timeout_ms,
      id_generator=self.id_generator,
      http_transport=self.http_transport,
      prompt_converter=self.prompt_converter,
      transform_options=self.transform_options,
    ),
  )
}

///|
/// Select the default language model, which is a chat model for this package.
pub fn OpenAICompatibleProvider::language_model(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
) -> &@provider.LanguageModelV4 {
  let model = self.chat_language_model(model_id)
  model as &@provider.LanguageModelV4
}

///|
/// AI SDK-style camel-case spelling for `language_model`.
pub fn OpenAICompatibleProvider::languageModel(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Select a Chat Completions language model.
pub fn OpenAICompatibleProvider::chat_model(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Short alias for `chat_model`.
pub fn OpenAICompatibleProvider::chat(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat_model(model_id)
}

///|
/// AI SDK-style camel-case spelling for `chat_model`.
pub fn OpenAICompatibleProvider::chatModel(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat_model(model_id)
}

///|
fn OpenAICompatibleProvider::embedding_model_value(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleEmbeddingModelId,
) -> OpenAICompatibleEmbeddingModel {
  openai_compatible_embedding(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    api_key_environment_variable?=self.api_key_environment_variable,
    headers=self.headers,
    query_params=self.query_params,
    error_structure=self.error_structure,
    max_embeddings_per_call=self.max_embeddings_per_call,
    supports_parallel_calls=self.supports_parallel_calls,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Select a text embedding model.
pub fn OpenAICompatibleProvider::embedding_model(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  let model = self.embedding_model_value(model_id)
  model as &@provider.EmbeddingModelV4
}

///|
/// AI SDK-style camel-case spelling for `embedding_model`.
pub fn OpenAICompatibleProvider::embeddingModel(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
/// Short alias for `embedding_model`.
pub fn OpenAICompatibleProvider::embedding(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
/// Explicit text embedding model alias.
pub fn OpenAICompatibleProvider::text_embedding_model(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
/// Snake-case short alias for text embedding selection.
pub fn OpenAICompatibleProvider::text_embedding(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
/// AI SDK-style camel-case spelling for `text_embedding_model`.
pub fn OpenAICompatibleProvider::textEmbeddingModel(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleEmbeddingModelId,
) -> &@provider.EmbeddingModelV4 {
  self.embedding_model(model_id)
}

///|
fn OpenAICompatibleProvider::completion_language_model(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleCompletionModelId,
) -> OpenAICompatibleCompletionLanguageModel {
  OpenAICompatibleCompletionLanguageModel::new(
    model_id,
    OpenAICompatibleCompletionConfig::new(
      provider_name="\{self.provider_name}.completion",
      base_url=self.base_url,
      api_key=self.api_key,
      api_key_environment_variable?=self.api_key_environment_variable,
      headers=self.headers,
      query_params=self.query_params,
      include_usage=self.include_usage,
      error_structure=self.error_structure,
      idle_timeout_ms=self.idle_timeout_ms,
      http_transport=self.http_transport,
    ),
  )
}

///|
/// Select an OpenAI-compatible `/completions` language model.
pub fn OpenAICompatibleProvider::completion_model(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleCompletionModelId,
) -> &@provider.LanguageModelV4 {
  let model = self.completion_language_model(model_id)
  model as &@provider.LanguageModelV4
}

///|
/// AI SDK-style camel-case spelling for `completion_model`.
pub fn OpenAICompatibleProvider::completionModel(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleCompletionModelId,
) -> &@provider.LanguageModelV4 {
  self.completion_model(model_id)
}

///|
/// Short alias for `completion_model`.
pub fn OpenAICompatibleProvider::completion(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleCompletionModelId,
) -> &@provider.LanguageModelV4 {
  self.completion_model(model_id)
}

///|
fn OpenAICompatibleProvider::image_model_value(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> OpenAICompatibleImageModel {
  openai_compatible_image(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    api_key_environment_variable?=self.api_key_environment_variable,
    headers=self.headers,
    query_params=self.query_params,
    error_structure=self.error_structure,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport?=self.custom_http_transport,
  )
}

///|
/// Select an OpenAI-compatible image model.
pub fn OpenAICompatibleProvider::image_model(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> &@provider.ImageModelV4 {
  let model = self.image_model_value(model_id)
  model as &@provider.ImageModelV4
}

///|
/// AI SDK-style camel-case spelling for `image_model`.
pub fn OpenAICompatibleProvider::imageModel(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> &@provider.ImageModelV4 {
  self.image_model(model_id)
}

///|
/// Short alias for `image_model`.
pub fn OpenAICompatibleProvider::image(
  self : OpenAICompatibleProvider,
  model_id : String,
) -> &@provider.ImageModelV4 {
  self.image_model(model_id)
}

///|
/// Construct an OpenAI-compatible Chat Completions model directly.
pub fn openai_compatible(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : OpenAICompatibleChatModelId,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  query_params? : Map[String, String] = Map([]),
  include_usage? : Bool = false,
  supports_structured_outputs? : Bool = false,
  transform_request_body? : (Json) -> Json = value => value,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  metadata_extractor? : OpenAICompatibleMetadataExtractor,
  convert_usage? : OpenAICompatibleUsageConverter = convert_openai_compatible_chat_usage,
  idle_timeout_ms? : Int = 120_000,
  supports_top_k? : Bool = false,
  supports_frequency_penalty? : Bool = true,
  supported_urls? : Array[@provider.SupportedUrlRule] = [],
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
  generate_reasoning_ids? : Bool = false,
  prompt_converter? : OpenAICompatibleV4PromptConverter = default_openai_compatible_v4_prompt_converter,
  transform_options? : OpenAICompatibleV4OptionsTransformer = identity_compatible_v4_options,
) -> &@provider.LanguageModelV4 {
  let model = OpenAICompatibleChatLanguageModel::new(
    model_id,
    OpenAICompatibleChatConfig::new(
      provider_name="\{provider_name}.chat",
      base_url~,
      api_key~,
      api_key_environment_variable?,
      headers~,
      query_params~,
      include_usage~,
      supports_structured_outputs~,
      supports_top_k~,
      supports_frequency_penalty~,
      supported_urls~,
      transform_request_body~,
      error_structure~,
      metadata_extractor?,
      convert_usage~,
      idle_timeout_ms~,
      id_generator?,
      generate_reasoning_ids~,
      http_transport?,
      prompt_converter~,
      transform_options~,
    ),
  )
  model as &@provider.LanguageModelV4
}

///|
/// Construct an OpenAI-compatible `/completions` model directly.
pub fn openai_compatible_completion(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : OpenAICompatibleCompletionModelId,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  query_params? : Map[String, String] = Map([]),
  include_usage? : Bool = false,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
) -> &@provider.LanguageModelV4 {
  let model = OpenAICompatibleCompletionLanguageModel::new(
    model_id,
    OpenAICompatibleCompletionConfig::new(
      provider_name="\{provider_name}.completion",
      base_url~,
      api_key~,
      api_key_environment_variable?,
      headers~,
      query_params~,
      include_usage~,
      error_structure~,
      idle_timeout_ms~,
      http_transport?,
    ),
  )
  model as &@provider.LanguageModelV4
}
