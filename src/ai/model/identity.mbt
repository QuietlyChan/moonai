///|
/// Stable identity for a provider model.
///
/// Provider traits describe how a model is called; this value describes which
/// model is selected. Registries and middleware can therefore share identity
/// logic without depending on a provider wire protocol.
pub(all) struct ModelId {
  provider : String
  model_id : String
} derive(Debug, Eq)

///|
/// Construct a model identity.
pub fn ModelId::new(provider~ : String, model_id~ : String) -> ModelId {
  { provider, model_id }
}

///|
/// Read the provider name.
pub fn ModelId::provider(self : ModelId) -> String {
  self.provider
}

///|
/// Read the provider model identifier.
pub fn ModelId::model_id(self : ModelId) -> String {
  self.model_id
}

///|
/// Return the canonical registry key (`provider:model-id`).
pub fn ModelId::key(self : ModelId) -> String {
  self.provider + ":" + self.model_id
}

///|
/// Parse the canonical `provider:model-id` registry key.
///
/// Only the first colon separates provider and model. This matches AI SDK's
/// provider registry and permits provider-specific model ids containing a
/// colon.
pub fn ModelId::parse(value : String) -> ModelId? {
  let parts = value.split(":").to_array()
  guard parts.length() >= 2 else { return None }
  let provider = parts[0].trim().to_owned()
  let model_parts : Array[String] = []
  for index = 1; index < parts.length(); index = index + 1 {
    model_parts.push(parts[index].to_owned())
  }
  let model_id = model_parts.join(":").trim().to_owned()
  if provider == "" || model_id == "" {
    None
  } else {
    Some(ModelId::new(provider~, model_id~))
  }
}

///|
/// Parse a registry key and raise when it is not provider-qualified.
pub suberror InvalidModelIdError {
  InvalidModelIdError(value~ : String)
} derive(Debug, Eq)

///|
/// Parse a canonical model key with a typed validation error.
pub fn parse_model_id(value : String) -> ModelId raise InvalidModelIdError {
  match ModelId::parse(value) {
    Some(id) => id
    None => raise InvalidModelIdError(value~)
  }
}

///|
/// Model contract requested from a registry.
///
/// AI SDK reports the requested model type in `NoSuchModelError`; retaining it
/// is particularly important when one provider uses the same model id for
/// several modalities.
pub(all) enum ModelType {
  Chat
  Completion
  Embedding
  Reranking
  Image
  Video
  Speech
  Transcription
  SpeechTranslation
  Realtime
} derive(Debug, Eq)

///|
/// Raised when a registry cannot resolve the requested model identity and
/// contract.
pub(all) suberror NoSuchModelError {
  NoSuchModelError(model_id~ : ModelId, model_type~ : ModelType)
} derive(Debug, Eq)

///|
/// Return the missing model identity.
pub fn NoSuchModelError::model_id(self : NoSuchModelError) -> ModelId {
  match self {
    NoSuchModelError(model_id~, ..) => model_id
  }
}

///|
/// Return the requested model contract.
pub fn NoSuchModelError::model_type(self : NoSuchModelError) -> ModelType {
  match self {
    NoSuchModelError(model_type~, ..) => model_type
  }
}

///|
/// Extract the identity exposed by a language model.
pub fn model_id_of_language_model(
  model : &@provider.LanguageModelV4,
) -> ModelId {
  ModelId::new(provider=model.provider(), model_id=model.model_id())
}

///|
/// Extract the identity exposed by a completion model.
pub fn model_id_of_completion(model : &@provider.CompletionModel) -> ModelId {
  ModelId::new(provider=model.provider(), model_id=model.model_id())
}

///|
/// Extract the identity exposed by an embedding model.
pub fn model_id_of_embedding(model : &@provider.EmbeddingModelV4) -> ModelId {
  ModelId::new(provider=model.provider(), model_id=model.model_id())
}

///|
/// Extract the identity exposed by a reranking model.
pub fn model_id_of_reranking(model : &@provider.RerankingModelV4) -> ModelId {
  ModelId::new(provider=model.provider(), model_id=model.model_id())
}

///|
/// Extract the identity exposed by an image model.
pub fn model_id_of_image(model : &@provider.ImageModelV4) -> ModelId {
  ModelId::new(provider=model.provider(), model_id=model.model_id())
}

///|
/// Extract the identity exposed by a video model.
pub fn model_id_of_video(model : &@provider.VideoModelV4) -> ModelId {
  ModelId::new(provider=model.provider(), model_id=model.model_id())
}

///|
/// Extract the identity exposed by a speech model.
pub fn model_id_of_speech(model : &@provider.SpeechModelV4) -> ModelId {
  ModelId::new(provider=model.provider(), model_id=model.model_id())
}

///|
/// Extract the identity exposed by a transcription model.
pub fn model_id_of_transcription(
  model : &@provider.TranscriptionModelV4,
) -> ModelId {
  ModelId::new(provider=model.provider(), model_id=model.model_id())
}

///|
/// Extract the identity exposed by a speech translation model.
pub fn model_id_of_speech_translation(
  model : &@provider.SpeechTranslationModelV4,
) -> ModelId {
  ModelId::new(provider=model.provider(), model_id=model.model_id())
}

///|
/// Extract the identity exposed by a realtime model.
pub fn model_id_of_realtime(model : &@provider.RealtimeModelV4) -> ModelId {
  ModelId::new(provider=model.provider(), model_id=model.model_id())
}
