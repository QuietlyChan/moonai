///|
/// Provider-specific normalization hook for a Chat Completions call.
///
/// Most OpenAI-compatible providers can use the normalized call options as-is.
/// Providers with a compatible wire protocol but different semantics (for
/// example Alibaba's thinking controls) can translate top-level options into
/// their namespace before the shared encoder runs.
pub type OpenAICompatibleChatOptionsTransformer = (@provider.ChatCallOptions) -> @provider.ChatCallOptions

///|
fn identity_chat_options(
  options : @provider.ChatCallOptions,
) -> @provider.ChatCallOptions {
  options
}

///|
/// Configuration shared by models served by one OpenAI-compatible endpoint.
pub struct OpenAICompatibleProvider {
  priv provider_name : String
  priv api_key : String
  priv api_key_environment_variable : String?
  priv base_url : String
  priv headers : Map[String, String]
  priv query_params : Map[String, String]
  priv preserve_reasoning : Bool
  priv include_usage : Bool
  priv supports_structured_outputs : Bool
  priv supports_top_k : Bool
  priv supports_frequency_penalty : Bool
  priv supported_url_rules : Array[@provider.SupportedUrlRule]
  priv prompt_converter : OpenAICompatiblePromptConverter
  priv transform_request_body : (Json) -> Json
  priv error_structure : OpenAICompatibleErrorStructure
  priv metadata_extractor : OpenAICompatibleMetadataExtractor?
  priv convert_usage : (Json) -> @provider.Usage
  priv max_embeddings_per_call : Int
  priv supports_parallel_calls : Bool
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
  priv transform_chat_options : OpenAICompatibleChatOptionsTransformer
}

///|
fn openai_compatible_user_agent_suffix(provider_name : String) -> String {
  if provider_name.has_prefix("alibaba") {
    "moonai/alibaba/\{VERSION}"
  } else if provider_name.has_prefix("openai-compatible") {
    "moonai/openai-compatible/\{VERSION}"
  } else if provider_name.has_prefix("openai") {
    "moonai/openai/\{VERSION}"
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
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = false,
  supports_structured_outputs? : Bool = false,
  prompt_converter? : OpenAICompatiblePromptConverter = default_openai_compatible_prompt_converter,
  transform_request_body? : (Json) -> Json = value => value,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  metadata_extractor? : OpenAICompatibleMetadataExtractor,
  convert_usage? : (Json) -> @provider.Usage = convert_openai_compatible_chat_usage,
  idle_timeout_ms? : Int = 120_000,
  max_embeddings_per_call? : Int = 2048,
  supports_parallel_calls? : Bool = true,
  supports_top_k? : Bool = false,
  supports_frequency_penalty? : Bool = true,
  supported_urls? : Array[@provider.SupportedUrlRule] = [],
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
  transform_chat_options? : OpenAICompatibleChatOptionsTransformer = identity_chat_options,
) -> OpenAICompatibleProvider {
  {
    provider_name,
    api_key,
    api_key_environment_variable,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    query_params: @provider_utils.copy_headers(query_params),
    preserve_reasoning,
    include_usage,
    supports_structured_outputs,
    supports_top_k,
    supports_frequency_penalty,
    supported_url_rules: supported_urls.copy(),
    prompt_converter,
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
    transform_chat_options,
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
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = false,
  supports_structured_outputs? : Bool = false,
  prompt_converter? : OpenAICompatiblePromptConverter = default_openai_compatible_prompt_converter,
  transform_request_body? : (Json) -> Json = value => value,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  metadata_extractor? : OpenAICompatibleMetadataExtractor,
  convert_usage? : (Json) -> @provider.Usage = convert_openai_compatible_chat_usage,
  idle_timeout_ms? : Int = 120_000,
  max_embeddings_per_call? : Int = 2048,
  supports_parallel_calls? : Bool = true,
  supports_top_k? : Bool = false,
  supports_frequency_penalty? : Bool = true,
  supported_urls? : Array[@provider.SupportedUrlRule] = [],
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
  transform_chat_options? : OpenAICompatibleChatOptionsTransformer = identity_chat_options,
) -> OpenAICompatibleProvider {
  create_openai_compatible(
    provider_name~,
    base_url~,
    api_key~,
    headers~,
    query_params~,
    preserve_reasoning~,
    include_usage~,
    supports_structured_outputs~,
    prompt_converter~,
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
    transform_chat_options~,
  )
}

///|
/// Select the protocol-level Chat Completions model.
pub fn OpenAICompatibleProvider::chat_model_wire(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
) -> OpenAICompatibleChatModel {
  self.chat_model_wire_with_reasoning_ids(model_id, false)
}

///|
fn OpenAICompatibleProvider::chat_model_wire_with_reasoning_ids(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
  generate_reasoning_ids : Bool,
) -> OpenAICompatibleChatModel {
  {
    provider_name: "\{self.provider_name}.chat",
    api_key: self.api_key,
    api_key_environment_variable: self.api_key_environment_variable,
    base_url: self.base_url,
    model_id,
    headers: @provider_utils.copy_headers(self.headers),
    query_params: @provider_utils.copy_headers(self.query_params),
    preserve_reasoning: self.preserve_reasoning,
    include_usage: self.include_usage,
    supports_structured_outputs: self.supports_structured_outputs,
    supports_top_k: self.supports_top_k,
    supports_frequency_penalty: self.supports_frequency_penalty,
    supported_url_rules: self.supported_url_rules.copy(),
    prompt_converter: self.prompt_converter,
    transform_request_body: self.transform_request_body,
    error_structure: self.error_structure,
    metadata_extractor: self.metadata_extractor,
    convert_usage: self.convert_usage,
    idle_timeout_ms: self.idle_timeout_ms,
    id_generator: self.id_generator,
    generate_reasoning_ids,
    http_transport: self.http_transport,
    transform_chat_options: self.transform_chat_options,
  }
}

///|
/// Select the default language model, which is a chat model for this package.
pub fn OpenAICompatibleProvider::language_model(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
) -> OpenAICompatibleLanguageModelV4 {
  OpenAICompatibleLanguageModelV4::new(self.chat_model_wire(model_id))
}

///|
/// AI SDK-style camel-case spelling for `language_model`.
pub fn OpenAICompatibleProvider::languageModel(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
) -> OpenAICompatibleLanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Select a Chat Completions language model.
pub fn OpenAICompatibleProvider::chat_model(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
) -> OpenAICompatibleLanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Short alias for `chat_model`.
pub fn OpenAICompatibleProvider::chat(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
) -> OpenAICompatibleLanguageModelV4 {
  self.chat_model(model_id)
}

///|
/// AI SDK-style camel-case spelling for `chat_model`.
pub fn OpenAICompatibleProvider::chatModel(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleChatModelId,
) -> OpenAICompatibleLanguageModelV4 {
  self.chat_model(model_id)
}

///|
/// Select a text embedding model.
pub fn OpenAICompatibleProvider::embedding_model(
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
/// AI SDK-style camel-case spelling for `embedding_model`.
pub fn OpenAICompatibleProvider::embeddingModel(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleEmbeddingModelId,
) -> OpenAICompatibleEmbeddingModel {
  self.embedding_model(model_id)
}

///|
/// Short embedding alias matching the OpenAI provider API.
pub fn OpenAICompatibleProvider::embedding(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleEmbeddingModelId,
) -> OpenAICompatibleEmbeddingModel {
  self.embedding_model(model_id)
}

///|
/// Convenience alias for text embedding model selection.
pub fn OpenAICompatibleProvider::text_embedding_model(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleEmbeddingModelId,
) -> OpenAICompatibleEmbeddingModel {
  self.embedding_model(model_id)
}

///|
/// Snake-case short alias for text embedding model selection.
pub fn OpenAICompatibleProvider::text_embedding(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleEmbeddingModelId,
) -> OpenAICompatibleEmbeddingModel {
  self.embedding_model(model_id)
}

///|
/// AI SDK-style camel-case spelling for `text_embedding_model`.
pub fn OpenAICompatibleProvider::textEmbeddingModel(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleEmbeddingModelId,
) -> OpenAICompatibleEmbeddingModel {
  self.embedding_model(model_id)
}

///|
/// Select the protocol-level `/completions` model.
pub fn OpenAICompatibleProvider::completion_model_wire(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleCompletionModelId,
) -> OpenAICompatibleCompletionModel {
  openai_compatible_completion_wire(
    provider_name=self.provider_name,
    base_url=self.base_url,
    model_id~,
    api_key=self.api_key,
    api_key_environment_variable?=self.api_key_environment_variable,
    headers=self.headers,
    query_params=self.query_params,
    include_usage=self.include_usage,
    error_structure=self.error_structure,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// Select a `/completions` language model through the V4 contract.
pub fn OpenAICompatibleProvider::completion_model(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleCompletionModelId,
) -> OpenAICompatibleCompletionLanguageModelV4 {
  OpenAICompatibleCompletionLanguageModelV4::new(
    self.completion_model_wire(model_id),
  )
}

///|
/// AI SDK-style camel-case spelling for `completion_model`.
pub fn OpenAICompatibleProvider::completionModel(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleCompletionModelId,
) -> OpenAICompatibleCompletionLanguageModelV4 {
  self.completion_model(model_id)
}

///|
/// Short alias for completion language-model selection.
pub fn OpenAICompatibleProvider::completion(
  self : OpenAICompatibleProvider,
  model_id : OpenAICompatibleCompletionModelId,
) -> OpenAICompatibleCompletionLanguageModelV4 {
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
    api_key_environment_variable?=self.api_key_environment_variable,
    headers=self.headers,
    query_params=self.query_params,
    error_structure=self.error_structure,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
  )
}

///|
/// AI SDK-style camel-case spelling for `image_model`.
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
  priv api_key_environment_variable : String?
  priv base_url : String
  priv model_id : OpenAICompatibleChatModelId
  priv headers : Map[String, String]
  priv query_params : Map[String, String]
  priv preserve_reasoning : Bool
  priv include_usage : Bool
  priv supports_structured_outputs : Bool
  priv supports_top_k : Bool
  priv supports_frequency_penalty : Bool
  priv supported_url_rules : Array[@provider.SupportedUrlRule]
  priv prompt_converter : OpenAICompatiblePromptConverter
  priv transform_request_body : (Json) -> Json
  priv error_structure : OpenAICompatibleErrorStructure
  priv metadata_extractor : OpenAICompatibleMetadataExtractor?
  priv convert_usage : (Json) -> @provider.Usage
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv generate_reasoning_ids : Bool
  priv http_transport : &@provider_utils.HttpTransport
  priv transform_chat_options : OpenAICompatibleChatOptionsTransformer
}

///|
/// Construct the low-level OpenAI-compatible Chat Completions wire model.
pub fn openai_compatible_wire(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : OpenAICompatibleChatModelId,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  query_params? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = false,
  supports_structured_outputs? : Bool = false,
  prompt_converter? : OpenAICompatiblePromptConverter = default_openai_compatible_prompt_converter,
  transform_request_body? : (Json) -> Json = value => value,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  metadata_extractor? : OpenAICompatibleMetadataExtractor,
  convert_usage? : (Json) -> @provider.Usage = convert_openai_compatible_chat_usage,
  idle_timeout_ms? : Int = 120_000,
  supports_top_k? : Bool = false,
  supports_frequency_penalty? : Bool = true,
  supported_urls? : Array[@provider.SupportedUrlRule] = [],
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
  generate_reasoning_ids? : Bool = false,
  transform_chat_options? : OpenAICompatibleChatOptionsTransformer = identity_chat_options,
) -> OpenAICompatibleChatModel {
  create_openai_compatible(
    provider_name~,
    base_url~,
    api_key~,
    headers~,
    query_params~,
    preserve_reasoning~,
    include_usage~,
    supports_structured_outputs~,
    prompt_converter~,
    transform_request_body~,
    error_structure~,
    metadata_extractor?,
    convert_usage~,
    idle_timeout_ms~,
    supports_top_k~,
    supports_frequency_penalty~,
    supported_urls~,
    http_transport?,
    api_key_environment_variable?,
    id_generator?,
    transform_chat_options~,
  ).chat_model_wire_with_reasoning_ids(model_id, generate_reasoning_ids)
}

///|
/// Construct the default V4 OpenAI-compatible language model directly.
pub fn openai_compatible(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : OpenAICompatibleChatModelId,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  query_params? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = false,
  supports_structured_outputs? : Bool = false,
  prompt_converter? : OpenAICompatiblePromptConverter = default_openai_compatible_prompt_converter,
  transform_request_body? : (Json) -> Json = value => value,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
  metadata_extractor? : OpenAICompatibleMetadataExtractor,
  convert_usage? : (Json) -> @provider.Usage = convert_openai_compatible_chat_usage,
  idle_timeout_ms? : Int = 120_000,
  supports_top_k? : Bool = false,
  supports_frequency_penalty? : Bool = true,
  supported_urls? : Array[@provider.SupportedUrlRule] = [],
  http_transport? : &@provider_utils.HttpTransport,
  api_key_environment_variable? : String,
  id_generator? : @provider_utils.IdGenerator,
  transform_chat_options? : OpenAICompatibleChatOptionsTransformer = identity_chat_options,
) -> OpenAICompatibleLanguageModelV4 {
  OpenAICompatibleLanguageModelV4::new(
    openai_compatible_wire(
      provider_name~,
      base_url~,
      model_id~,
      api_key~,
      headers~,
      query_params~,
      preserve_reasoning~,
      include_usage~,
      supports_structured_outputs~,
      prompt_converter~,
      transform_request_body~,
      error_structure~,
      metadata_extractor?,
      convert_usage~,
      idle_timeout_ms~,
      supports_top_k~,
      supports_frequency_penalty~,
      supported_urls~,
      http_transport?,
      api_key_environment_variable?,
      id_generator?,
      transform_chat_options~,
    ),
  )
}

///|
fn OpenAICompatibleChatModel::chat_completions_url(
  self : OpenAICompatibleChatModel,
) -> String {
  @provider_utils.append_query(
    @provider_utils.append_path(self.base_url, "/chat/completions"),
    self.query_params,
  )
}

///|
fn OpenAICompatibleChatModel::request_headers(
  self : OpenAICompatibleChatModel,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  let api_key = match self.api_key_environment_variable {
    Some(environment_variable_name) =>
      Some(
        @provider_utils.load_api_key(
          self.api_key,
          environment_variable_name~,
          description=self.provider_name,
        ),
      )
    None if self.api_key != "" => Some(self.api_key)
    None => None
  }
  match api_key {
    Some(value) => headers["Authorization"] = "Bearer \{value}"
    None => ()
  }
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    [openai_compatible_user_agent_suffix(self.provider_name)],
  )
}

///|
pub impl @provider.ChatModel for OpenAICompatibleChatModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.ChatModel for OpenAICompatibleChatModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.ChatModel for OpenAICompatibleChatModel with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.supported_url_rules.copy()
}

///|
pub impl @provider.ChatModel for OpenAICompatibleChatModel with fn generate(
  self,
  options,
) {
  self.generate_chat(options)
}

///|
pub impl @provider.ChatModel for OpenAICompatibleChatModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_chat(options, on_event)
}
