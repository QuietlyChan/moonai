///|
/// Registry of provider factories keyed by application-defined provider ids.
///
/// Unlike `ModelRegistry`, this registry creates models lazily from a provider
/// factory. It mirrors AI SDK's `createProviderRegistry` abstraction and keeps
/// model selection independent from concrete provider packages.
pub struct ProviderRegistry {
  priv providers : Map[String, &@provider.ProviderV4]
  priv separator : String
  priv language_model_middleware : @provider.LanguageModelV4Middleware?
  priv image_model_middleware : @provider.ImageModelV4Middleware?
}

///|
/// Create an empty provider registry.
pub fn ProviderRegistry::new(
  separator? : String = ":",
  language_model_middleware? : @provider.LanguageModelV4Middleware,
  image_model_middleware? : @provider.ImageModelV4Middleware,
) -> ProviderRegistry raise @provider.InvalidArgumentError {
  guard separator != "" else {
    raise @provider.InvalidArgumentError(
      argument="separator",
      message="provider registry separator must not be empty",
    )
  }
  {
    providers: Map([]),
    separator,
    language_model_middleware,
    image_model_middleware,
  }
}

///|
/// Return the separator between provider and model ids.
pub fn ProviderRegistry::separator(self : ProviderRegistry) -> String {
  self.separator
}

///|
/// Register a provider under an explicit id, replacing an existing entry.
pub fn ProviderRegistry::with_provider(
  self : ProviderRegistry,
  provider_id : String,
  provider : &@provider.ProviderV4,
) -> ProviderRegistry raise @provider.InvalidArgumentError {
  let normalized = provider_id.trim().to_owned()
  guard normalized != "" else {
    raise @provider.InvalidArgumentError(
      argument="provider_id",
      message="provider registry id must not be empty",
    )
  }
  guard !normalized.contains(self.separator) else {
    raise @provider.InvalidArgumentError(
      argument="provider_id",
      message="provider registry id must not contain the configured separator",
    )
  }
  self.providers[normalized] = provider
  self
}

///|
/// Return the currently registered provider ids.
pub fn ProviderRegistry::provider_ids(self : ProviderRegistry) -> Array[String] {
  let ids : Array[String] = []
  for entry in self.providers.iter2() {
    let (id, _) = entry
    ids.push(id)
  }
  ids
}

///|
fn ProviderRegistry::provider(
  self : ProviderRegistry,
  provider_id : String,
) -> &@provider.ProviderV4 raise NoSuchProviderError {
  match self.providers.get(provider_id) {
    Some(provider) => provider
    None =>
      raise NoSuchProviderError(
        provider_id~,
        available_provider_ids=self.provider_ids(),
      )
  }
}

///|
fn ProviderRegistry::split_model_id(
  self : ProviderRegistry,
  value : String,
  model_type : @model.ModelType,
) -> (String, String) raise InvalidRegistryModelIdError {
  let parts = value.split(self.separator).to_array()
  guard parts.length() >= 2 else {
    raise InvalidRegistryModelIdError(
      value~,
      separator=self.separator,
      model_type~,
    )
  }
  let provider_id = parts[0].trim().to_owned()
  let model_parts : Array[String] = []
  for index = 1; index < parts.length(); index = index + 1 {
    model_parts.push(parts[index].to_owned())
  }
  let model_id = model_parts.join(self.separator).trim().to_owned()
  guard provider_id != "" && model_id != "" else {
    raise InvalidRegistryModelIdError(
      value~,
      separator=self.separator,
      model_type~,
    )
  }
  (provider_id, model_id)
}

///|
fn no_such_model(
  model_id : String,
  model_type : @provider.NoSuchModelType,
) -> @provider.NoSuchModelError {
  @provider.NoSuchModelError(model_id~, model_type~)
}

///|
/// Resolve a V4 language model from a provider-qualified id.
pub fn ProviderRegistry::language_model(
  self : ProviderRegistry,
  id : String,
) -> &@provider.LanguageModelV4 raise {
  let (provider_id, model_id) = self.split_model_id(id, @model.Chat)
  let model = self.provider(provider_id).language_model(model_id)
  match self.language_model_middleware {
    Some(middleware) => @model.wrap_language_model_v4(model, middleware)
    None => model
  }
}

///|
/// Resolve an embedding model from a provider-qualified id.
pub fn ProviderRegistry::embedding_model(
  self : ProviderRegistry,
  id : String,
) -> &@provider.EmbeddingModelV4 raise {
  let (provider_id, model_id) = self.split_model_id(id, @model.Embedding)
  self.provider(provider_id).embedding_model(model_id)
}

///|
/// Resolve a reranking model from a provider-qualified id.
pub fn ProviderRegistry::reranking_model(
  self : ProviderRegistry,
  id : String,
) -> &@provider.RerankingModelV4 raise {
  let (provider_id, model_id) = self.split_model_id(id, @model.Reranking)
  match self.provider(provider_id).reranking_model(model_id) {
    Some(model) => model
    None => raise no_such_model(id, @provider.RerankingModel)
  }
}

///|
/// Resolve an image model from a provider-qualified id.
pub fn ProviderRegistry::image_model(
  self : ProviderRegistry,
  id : String,
) -> &@provider.ImageModelV4 raise {
  let (provider_id, model_id) = self.split_model_id(id, @model.Image)
  let model = self.provider(provider_id).image_model(model_id)
  match self.image_model_middleware {
    Some(middleware) => @model.wrap_image_model_v4(model, middleware)
    None => model
  }
}

///|
/// Resolve a speech model from a provider-qualified id.
pub fn ProviderRegistry::speech_model(
  self : ProviderRegistry,
  id : String,
) -> &@provider.SpeechModelV4 raise {
  let (provider_id, model_id) = self.split_model_id(id, @model.Speech)
  match self.provider(provider_id).speech_model(model_id) {
    Some(model) => model
    None => raise no_such_model(id, @provider.SpeechModel)
  }
}

///|
/// Resolve a transcription model from a provider-qualified id.
pub fn ProviderRegistry::transcription_model(
  self : ProviderRegistry,
  id : String,
) -> &@provider.TranscriptionModelV4 raise {
  let (provider_id, model_id) = self.split_model_id(id, @model.Transcription)
  match self.provider(provider_id).transcription_model(model_id) {
    Some(model) => model
    None => raise no_such_model(id, @provider.TranscriptionModel)
  }
}

///|
/// Resolve a provider-level FilesV4 service.
pub fn ProviderRegistry::files(
  self : ProviderRegistry,
  provider_id : String,
) -> &@provider.FilesV4 raise {
  match self.provider(provider_id).files() {
    Some(files) => files
    None =>
      raise NoSuchProviderCapabilityError(provider_id~, capability="files")
  }
}

///|
/// Resolve a provider-level SkillsV4 service.
pub fn ProviderRegistry::skills(
  self : ProviderRegistry,
  provider_id : String,
) -> &@provider.SkillsV4 raise {
  match self.provider(provider_id).skills() {
    Some(skills) => skills
    None =>
      raise NoSuchProviderCapabilityError(provider_id~, capability="skills")
  }
}

///|
/// Construct a registry from a provider map.
pub fn create_provider_registry(
  providers : Map[String, &@provider.ProviderV4],
  separator? : String = ":",
  language_model_middleware? : @provider.LanguageModelV4Middleware,
  image_model_middleware? : @provider.ImageModelV4Middleware,
) -> ProviderRegistry raise @provider.InvalidArgumentError {
  let registry = ProviderRegistry::new(
    separator~,
    language_model_middleware?,
    image_model_middleware?,
  )
  for entry in providers.iter2() {
    let (id, provider) = entry
    let _ = registry.with_provider(id, provider)
  }
  registry
}

///|
/// AI SDK-style camel-case spelling for `create_provider_registry`.
pub fn createProviderRegistry(
  providers : Map[String, &@provider.ProviderV4],
  separator? : String = ":",
  language_model_middleware? : @provider.LanguageModelV4Middleware,
  image_model_middleware? : @provider.ImageModelV4Middleware,
) -> ProviderRegistry raise @provider.InvalidArgumentError {
  create_provider_registry(
    providers,
    separator~,
    language_model_middleware?,
    image_model_middleware?,
  )
}
