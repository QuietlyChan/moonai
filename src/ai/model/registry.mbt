///|
/// Registry of concrete model trait objects, separated by model contract.
///
/// Registries live above provider packages: providers create models, while
/// high-level workflows and middleware resolve direct or named references
/// without depending on provider-specific wire formats.
pub struct ModelRegistry {
  priv language_models : Map[String, &@provider.LanguageModelV4]
  priv completion_models : Map[String, &@provider.CompletionModel]
  priv embedding_models : Map[String, &@provider.EmbeddingModelV4]
  priv reranking_models : Map[String, &@provider.RerankingModel]
  priv image_models : Map[String, &@provider.ImageModelV4]
  priv video_models : Map[String, &@provider.VideoModelV4]
  priv speech_models : Map[String, &@provider.SpeechModelV4]
  priv transcription_models : Map[String, &@provider.TranscriptionModelV4]
  priv speech_translation_models : Map[
    String,
    &@provider.SpeechTranslationModelV4,
  ]
  priv realtime_models : Map[String, &@provider.RealtimeModelV4]
}

///|
/// Create an empty model registry.
pub fn ModelRegistry::new() -> ModelRegistry {
  {
    language_models: Map([]),
    completion_models: Map([]),
    embedding_models: Map([]),
    reranking_models: Map([]),
    image_models: Map([]),
    video_models: Map([]),
    speech_models: Map([]),
    transcription_models: Map([]),
    speech_translation_models: Map([]),
    realtime_models: Map([]),
  }
}

///|
/// Register a language model under its canonical identity.
pub fn ModelRegistry::with_language_model(
  self : ModelRegistry,
  model : &@provider.LanguageModelV4,
) -> ModelRegistry {
  self.language_models[model_id_of_language_model(model).key()] = model
  self
}

///|
/// Register a completion model under its canonical identity.
pub fn ModelRegistry::with_completion_model(
  self : ModelRegistry,
  model : &@provider.CompletionModel,
) -> ModelRegistry {
  self.completion_models[model_id_of_completion(model).key()] = model
  self
}

///|
/// Register an embedding model under its canonical identity.
pub fn ModelRegistry::with_embedding_model(
  self : ModelRegistry,
  model : &@provider.EmbeddingModelV4,
) -> ModelRegistry {
  self.embedding_models[model_id_of_embedding(model).key()] = model
  self
}

///|
/// Register a reranking model under its canonical identity.
pub fn ModelRegistry::with_reranking_model(
  self : ModelRegistry,
  model : &@provider.RerankingModel,
) -> ModelRegistry {
  self.reranking_models[model_id_of_reranking(model).key()] = model
  self
}

///|
/// Register an image model under its canonical identity.
pub fn ModelRegistry::with_image_model(
  self : ModelRegistry,
  model : &@provider.ImageModelV4,
) -> ModelRegistry {
  self.image_models[model_id_of_image(model).key()] = model
  self
}

///|
/// Register a video model under its canonical identity.
pub fn ModelRegistry::with_video_model(
  self : ModelRegistry,
  model : &@provider.VideoModelV4,
) -> ModelRegistry {
  self.video_models[model_id_of_video(model).key()] = model
  self
}

///|
/// Register a speech model under its canonical identity.
pub fn ModelRegistry::with_speech_model(
  self : ModelRegistry,
  model : &@provider.SpeechModelV4,
) -> ModelRegistry {
  self.speech_models[model_id_of_speech(model).key()] = model
  self
}

///|
/// Register a transcription model under its canonical identity.
pub fn ModelRegistry::with_transcription_model(
  self : ModelRegistry,
  model : &@provider.TranscriptionModelV4,
) -> ModelRegistry {
  self.transcription_models[model_id_of_transcription(model).key()] = model
  self
}

///|
/// Register a speech translation model under its canonical identity.
pub fn ModelRegistry::with_speech_translation_model(
  self : ModelRegistry,
  model : &@provider.SpeechTranslationModelV4,
) -> ModelRegistry {
  self.speech_translation_models[model_id_of_speech_translation(model).key()] = model
  self
}

///|
/// Register a realtime model under its canonical identity.
pub fn ModelRegistry::with_realtime_model(
  self : ModelRegistry,
  model : &@provider.RealtimeModelV4,
) -> ModelRegistry {
  self.realtime_models[model_id_of_realtime(model).key()] = model
  self
}

///|
/// Look up a language model by canonical identity.
pub fn ModelRegistry::language_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.LanguageModelV4? {
  self.language_models.get(id.key())
}

///|
/// Look up a completion model by canonical identity.
pub fn ModelRegistry::completion_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.CompletionModel? {
  self.completion_models.get(id.key())
}

///|
/// Look up an embedding model by canonical identity.
pub fn ModelRegistry::embedding_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.EmbeddingModelV4? {
  self.embedding_models.get(id.key())
}

///|
/// Look up a reranking model by canonical identity.
pub fn ModelRegistry::reranking_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.RerankingModel? {
  self.reranking_models.get(id.key())
}

///|
/// Look up an image model by canonical identity.
pub fn ModelRegistry::image_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.ImageModelV4? {
  self.image_models.get(id.key())
}

///|
/// Look up a video model by canonical identity.
pub fn ModelRegistry::video_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.VideoModelV4? {
  self.video_models.get(id.key())
}

///|
/// Look up a speech model by canonical identity.
pub fn ModelRegistry::speech_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.SpeechModelV4? {
  self.speech_models.get(id.key())
}

///|
/// Look up a transcription model by canonical identity.
pub fn ModelRegistry::transcription_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.TranscriptionModelV4? {
  self.transcription_models.get(id.key())
}

///|
/// Look up a speech translation model by canonical identity.
pub fn ModelRegistry::speech_translation_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.SpeechTranslationModelV4? {
  self.speech_translation_models.get(id.key())
}

///|
/// Look up a realtime model by canonical identity.
pub fn ModelRegistry::realtime_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.RealtimeModelV4? {
  self.realtime_models.get(id.key())
}

///|
/// Look up a language model from a canonical registry key.
pub fn ModelRegistry::language_model_by_key(
  self : ModelRegistry,
  key : String,
) -> &@provider.LanguageModelV4? {
  match ModelId::parse(key) {
    Some(id) => self.language_model(id)
    None => None
  }
}

///|
/// Look up a completion model from a canonical registry key.
pub fn ModelRegistry::completion_model_by_key(
  self : ModelRegistry,
  key : String,
) -> &@provider.CompletionModel? {
  match ModelId::parse(key) {
    Some(id) => self.completion_model(id)
    None => None
  }
}

///|
/// Look up an embedding model from a canonical registry key.
pub fn ModelRegistry::embedding_model_by_key(
  self : ModelRegistry,
  key : String,
) -> &@provider.EmbeddingModelV4? {
  match ModelId::parse(key) {
    Some(id) => self.embedding_model(id)
    None => None
  }
}

///|
/// Look up a reranking model from a canonical registry key.
pub fn ModelRegistry::reranking_model_by_key(
  self : ModelRegistry,
  key : String,
) -> &@provider.RerankingModel? {
  match ModelId::parse(key) {
    Some(id) => self.reranking_model(id)
    None => None
  }
}

///|
/// Look up an image model from a canonical registry key.
pub fn ModelRegistry::image_model_by_key(
  self : ModelRegistry,
  key : String,
) -> &@provider.ImageModelV4? {
  match ModelId::parse(key) {
    Some(id) => self.image_model(id)
    None => None
  }
}

///|
/// Look up a video model from a canonical registry key.
pub fn ModelRegistry::video_model_by_key(
  self : ModelRegistry,
  key : String,
) -> &@provider.VideoModelV4? {
  match ModelId::parse(key) {
    Some(id) => self.video_model(id)
    None => None
  }
}

///|
/// Look up a speech model from a canonical registry key.
pub fn ModelRegistry::speech_model_by_key(
  self : ModelRegistry,
  key : String,
) -> &@provider.SpeechModelV4? {
  match ModelId::parse(key) {
    Some(id) => self.speech_model(id)
    None => None
  }
}

///|
/// Look up a transcription model from a canonical registry key.
pub fn ModelRegistry::transcription_model_by_key(
  self : ModelRegistry,
  key : String,
) -> &@provider.TranscriptionModelV4? {
  match ModelId::parse(key) {
    Some(id) => self.transcription_model(id)
    None => None
  }
}

///|
/// Look up a speech translation model from a canonical registry key.
pub fn ModelRegistry::speech_translation_model_by_key(
  self : ModelRegistry,
  key : String,
) -> &@provider.SpeechTranslationModelV4? {
  match ModelId::parse(key) {
    Some(id) => self.speech_translation_model(id)
    None => None
  }
}

///|
/// Look up a realtime model from a canonical registry key.
pub fn ModelRegistry::realtime_model_by_key(
  self : ModelRegistry,
  key : String,
) -> &@provider.RealtimeModelV4? {
  match ModelId::parse(key) {
    Some(id) => self.realtime_model(id)
    None => None
  }
}

///|
/// Resolve a required language model or raise `NoSuchModelError`.
pub fn ModelRegistry::require_language_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.LanguageModelV4 raise NoSuchModelError {
  match self.language_model(id) {
    Some(model) => model
    None => raise NoSuchModelError(model_id=id, model_type=Chat)
  }
}

///|
/// Resolve a required completion model or raise `NoSuchModelError`.
pub fn ModelRegistry::require_completion_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.CompletionModel raise NoSuchModelError {
  match self.completion_model(id) {
    Some(model) => model
    None => raise NoSuchModelError(model_id=id, model_type=Completion)
  }
}

///|
/// Resolve a required embedding model or raise `NoSuchModelError`.
pub fn ModelRegistry::require_embedding_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.EmbeddingModelV4 raise NoSuchModelError {
  match self.embedding_model(id) {
    Some(model) => model
    None => raise NoSuchModelError(model_id=id, model_type=Embedding)
  }
}

///|
/// Resolve a required reranking model or raise `NoSuchModelError`.
pub fn ModelRegistry::require_reranking_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.RerankingModel raise NoSuchModelError {
  match self.reranking_model(id) {
    Some(model) => model
    None => raise NoSuchModelError(model_id=id, model_type=Reranking)
  }
}

///|
/// Resolve a required image model or raise `NoSuchModelError`.
pub fn ModelRegistry::require_image_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.ImageModelV4 raise NoSuchModelError {
  match self.image_model(id) {
    Some(model) => model
    None => raise NoSuchModelError(model_id=id, model_type=Image)
  }
}

///|
/// Resolve a required video model or raise `NoSuchModelError`.
pub fn ModelRegistry::require_video_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.VideoModelV4 raise NoSuchModelError {
  match self.video_model(id) {
    Some(model) => model
    None => raise NoSuchModelError(model_id=id, model_type=Video)
  }
}

///|
/// Resolve a required speech model or raise `NoSuchModelError`.
pub fn ModelRegistry::require_speech_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.SpeechModelV4 raise NoSuchModelError {
  match self.speech_model(id) {
    Some(model) => model
    None => raise NoSuchModelError(model_id=id, model_type=Speech)
  }
}

///|
/// Resolve a required transcription model or raise `NoSuchModelError`.
pub fn ModelRegistry::require_transcription_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.TranscriptionModelV4 raise NoSuchModelError {
  match self.transcription_model(id) {
    Some(model) => model
    None => raise NoSuchModelError(model_id=id, model_type=Transcription)
  }
}

///|
/// Resolve a required speech translation model or raise `NoSuchModelError`.
pub fn ModelRegistry::require_speech_translation_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.SpeechTranslationModelV4 raise NoSuchModelError {
  match self.speech_translation_model(id) {
    Some(model) => model
    None => raise NoSuchModelError(model_id=id, model_type=SpeechTranslation)
  }
}

///|
/// Resolve a required realtime model or raise `NoSuchModelError`.
pub fn ModelRegistry::require_realtime_model(
  self : ModelRegistry,
  id : ModelId,
) -> &@provider.RealtimeModelV4 raise NoSuchModelError {
  match self.realtime_model(id) {
    Some(model) => model
    None => raise NoSuchModelError(model_id=id, model_type=Realtime)
  }
}

///|
/// Resolve a direct or named language model reference.
pub fn ModelRegistry::resolve_language_model(
  self : ModelRegistry,
  reference : LanguageModelV4Reference,
) -> &@provider.LanguageModelV4 raise NoSuchModelError {
  match reference {
    Instance(model) => model
    Named(id) => self.require_language_model(id)
  }
}

///|
/// Resolve a direct or named completion model reference.
pub fn ModelRegistry::resolve_completion_model(
  self : ModelRegistry,
  reference : CompletionModelReference,
) -> &@provider.CompletionModel raise NoSuchModelError {
  match reference {
    Instance(model) => model
    Named(id) => self.require_completion_model(id)
  }
}

///|
/// Resolve a direct or named embedding model reference.
pub fn ModelRegistry::resolve_embedding_model(
  self : ModelRegistry,
  reference : EmbeddingModelReference,
) -> &@provider.EmbeddingModelV4 raise NoSuchModelError {
  match reference {
    Instance(model) => model
    Named(id) => self.require_embedding_model(id)
  }
}

///|
/// Resolve a direct or named reranking model reference.
pub fn ModelRegistry::resolve_reranking_model(
  self : ModelRegistry,
  reference : RerankingModelReference,
) -> &@provider.RerankingModel raise NoSuchModelError {
  match reference {
    Instance(model) => model
    Named(id) => self.require_reranking_model(id)
  }
}

///|
/// Resolve a direct or named image model reference.
pub fn ModelRegistry::resolve_image_model(
  self : ModelRegistry,
  reference : ImageModelReference,
) -> &@provider.ImageModelV4 raise NoSuchModelError {
  match reference {
    Instance(model) => model
    Named(id) => self.require_image_model(id)
  }
}

///|
/// Resolve a direct or named video model reference.
pub fn ModelRegistry::resolve_video_model(
  self : ModelRegistry,
  reference : VideoModelReference,
) -> &@provider.VideoModelV4 raise NoSuchModelError {
  match reference {
    Instance(model) => model
    Named(id) => self.require_video_model(id)
  }
}

///|
/// Resolve a direct or named speech model reference.
pub fn ModelRegistry::resolve_speech_model(
  self : ModelRegistry,
  reference : SpeechModelReference,
) -> &@provider.SpeechModelV4 raise NoSuchModelError {
  match reference {
    Instance(model) => model
    Named(id) => self.require_speech_model(id)
  }
}

///|
/// Resolve a direct or named transcription model reference.
pub fn ModelRegistry::resolve_transcription_model(
  self : ModelRegistry,
  reference : TranscriptionModelReference,
) -> &@provider.TranscriptionModelV4 raise NoSuchModelError {
  match reference {
    Instance(model) => model
    Named(id) => self.require_transcription_model(id)
  }
}

///|
/// Resolve a direct or named speech translation model reference.
pub fn ModelRegistry::resolve_speech_translation_model(
  self : ModelRegistry,
  reference : SpeechTranslationModelReference,
) -> &@provider.SpeechTranslationModelV4 raise NoSuchModelError {
  match reference {
    Instance(model) => model
    Named(id) => self.require_speech_translation_model(id)
  }
}

///|
/// Resolve a direct or named realtime model reference.
pub fn ModelRegistry::resolve_realtime_model(
  self : ModelRegistry,
  reference : RealtimeModelReference,
) -> &@provider.RealtimeModelV4 raise NoSuchModelError {
  match reference {
    Instance(model) => model
    Named(id) => self.require_realtime_model(id)
  }
}
