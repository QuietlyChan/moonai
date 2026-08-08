///|
/// identity.
pub(all) enum LanguageModelV4Reference {
  Instance(&@provider.LanguageModelV4)
  Named(ModelId)
}

///|
/// Construct a direct V4 language model reference.
pub fn LanguageModelV4Reference::instance(
  model : &@provider.LanguageModelV4,
) -> LanguageModelV4Reference {
  Instance(model)
}

///|
/// Construct a named V4 language model reference.
pub fn LanguageModelV4Reference::named(
  provider~ : String,
  model_id~ : String,
) -> LanguageModelV4Reference {
  Named(ModelId::new(provider~, model_id~))
}

///|
/// A legacy completion model supplied directly or by identity.
pub(all) enum CompletionModelReference {
  Instance(&@provider.CompletionModel)
  Named(ModelId)
}

///|
/// Construct a direct completion model reference.
pub fn CompletionModelReference::instance(
  model : &@provider.CompletionModel,
) -> CompletionModelReference {
  Instance(model)
}

///|
/// Construct a named completion model reference.
pub fn CompletionModelReference::named(
  provider~ : String,
  model_id~ : String,
) -> CompletionModelReference {
  Named(ModelId::new(provider~, model_id~))
}

///|
/// An embedding model supplied directly or by identity.
pub(all) enum EmbeddingModelReference {
  Instance(&@provider.EmbeddingModelV4)
  Named(ModelId)
}

///|
/// Construct a direct embedding model reference.
pub fn EmbeddingModelReference::instance(
  model : &@provider.EmbeddingModelV4,
) -> EmbeddingModelReference {
  Instance(model)
}

///|
/// Construct a named embedding model reference.
pub fn EmbeddingModelReference::named(
  provider~ : String,
  model_id~ : String,
) -> EmbeddingModelReference {
  Named(ModelId::new(provider~, model_id~))
}

///|
/// A reranking model supplied directly or by identity.
pub(all) enum RerankingModelReference {
  Instance(&@provider.RerankingModelV4)
  Named(ModelId)
}

///|
/// Construct a direct reranking model reference.
pub fn RerankingModelReference::instance(
  model : &@provider.RerankingModelV4,
) -> RerankingModelReference {
  Instance(model)
}

///|
/// Construct a named reranking model reference.
pub fn RerankingModelReference::named(
  provider~ : String,
  model_id~ : String,
) -> RerankingModelReference {
  Named(ModelId::new(provider~, model_id~))
}

///|
/// An image model supplied directly or by identity.
pub(all) enum ImageModelReference {
  Instance(&@provider.ImageModelV4)
  Named(ModelId)
}

///|
/// Construct a direct image model reference.
pub fn ImageModelReference::instance(
  model : &@provider.ImageModelV4,
) -> ImageModelReference {
  Instance(model)
}

///|
/// Construct a named image model reference.
pub fn ImageModelReference::named(
  provider~ : String,
  model_id~ : String,
) -> ImageModelReference {
  Named(ModelId::new(provider~, model_id~))
}

///|
/// A video model supplied directly or by identity.
pub(all) enum VideoModelReference {
  Instance(&@provider.VideoModelV4)
  Named(ModelId)
}

///|
/// Construct a direct video model reference.
pub fn VideoModelReference::instance(
  model : &@provider.VideoModelV4,
) -> VideoModelReference {
  Instance(model)
}

///|
/// Construct a named video model reference.
pub fn VideoModelReference::named(
  provider~ : String,
  model_id~ : String,
) -> VideoModelReference {
  Named(ModelId::new(provider~, model_id~))
}

///|
/// A text-to-speech model supplied directly or by identity.
pub(all) enum SpeechModelReference {
  Instance(&@provider.SpeechModelV4)
  Named(ModelId)
}

///|
/// Construct a direct speech model reference.
pub fn SpeechModelReference::instance(
  model : &@provider.SpeechModelV4,
) -> SpeechModelReference {
  Instance(model)
}

///|
/// Construct a named speech model reference.
pub fn SpeechModelReference::named(
  provider~ : String,
  model_id~ : String,
) -> SpeechModelReference {
  Named(ModelId::new(provider~, model_id~))
}

///|
/// A transcription model supplied directly or by identity.
pub(all) enum TranscriptionModelReference {
  Instance(&@provider.TranscriptionModelV4)
  Named(ModelId)
}

///|
/// Construct a direct transcription model reference.
pub fn TranscriptionModelReference::instance(
  model : &@provider.TranscriptionModelV4,
) -> TranscriptionModelReference {
  Instance(model)
}

///|
/// Construct a named transcription model reference.
pub fn TranscriptionModelReference::named(
  provider~ : String,
  model_id~ : String,
) -> TranscriptionModelReference {
  Named(ModelId::new(provider~, model_id~))
}

///|
/// A streaming speech translation model supplied directly or by identity.
pub(all) enum SpeechTranslationModelReference {
  Instance(&@provider.SpeechTranslationModelV4)
  Named(ModelId)
}

///|
/// Construct a direct speech translation model reference.
pub fn SpeechTranslationModelReference::instance(
  model : &@provider.SpeechTranslationModelV4,
) -> SpeechTranslationModelReference {
  Instance(model)
}

///|
/// Construct a named speech translation model reference.
pub fn SpeechTranslationModelReference::named(
  provider~ : String,
  model_id~ : String,
) -> SpeechTranslationModelReference {
  Named(ModelId::new(provider~, model_id~))
}

///|
/// A realtime model supplied directly or by identity.
pub(all) enum RealtimeModelReference {
  Instance(&@provider.RealtimeModelV4)
  Named(ModelId)
}

///|
/// Construct a direct realtime model reference.
pub fn RealtimeModelReference::instance(
  model : &@provider.RealtimeModelV4,
) -> RealtimeModelReference {
  Instance(model)
}

///|
/// Construct a named realtime model reference.
pub fn RealtimeModelReference::named(
  provider~ : String,
  model_id~ : String,
) -> RealtimeModelReference {
  Named(ModelId::new(provider~, model_id~))
}
