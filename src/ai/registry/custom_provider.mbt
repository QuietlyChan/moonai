///|
/// A provider assembled from application-owned model instances.
///
/// This is the MoonBit counterpart of AI SDK's `customProvider`. Model maps
/// are checked before the optional fallback provider, so an application can
/// override only the models it needs while retaining the rest of a provider's
/// surface.
pub struct CustomProvider {
  priv provider_name : String
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
  priv files_service : &@provider.Files?
  priv skills_service : &@provider.Skills?
  priv fallback_provider : &@provider.Provider?
}

///|
/// Construct a custom provider from model maps and optional provider services.
///
/// The model maps use the model id requested by callers as their key. Empty
/// maps mean that the corresponding model family is delegated to the fallback
/// provider, when one is configured.
pub fn custom_provider(
  provider_name? : String = "custom",
  language_models? : Map[String, &@provider.LanguageModelV4] = Map([]),
  completion_models? : Map[String, &@provider.CompletionModel] = Map([]),
  embedding_models? : Map[String, &@provider.EmbeddingModelV4] = Map([]),
  reranking_models? : Map[String, &@provider.RerankingModel] = Map([]),
  image_models? : Map[String, &@provider.ImageModelV4] = Map([]),
  video_models? : Map[String, &@provider.VideoModelV4] = Map([]),
  speech_models? : Map[String, &@provider.SpeechModelV4] = Map([]),
  transcription_models? : Map[String, &@provider.TranscriptionModelV4] = Map([]),
  speech_translation_models? : Map[String, &@provider.SpeechTranslationModelV4] = Map([],
  ),
  realtime_models? : Map[String, &@provider.RealtimeModelV4] = Map([]),
  files? : &@provider.Files,
  skills? : &@provider.Skills,
  fallback_provider? : &@provider.Provider,
) -> CustomProvider raise @provider.InvalidArgumentError {
  let normalized_name = provider_name.trim().to_owned()
  guard normalized_name != "" else {
    raise @provider.InvalidArgumentError(
      argument="provider_name",
      message="custom provider name must not be empty",
    )
  }
  {
    provider_name: normalized_name,
    language_models,
    completion_models,
    embedding_models,
    reranking_models,
    image_models,
    video_models,
    speech_models,
    transcription_models,
    speech_translation_models,
    realtime_models,
    files_service: files,
    skills_service: skills,
    fallback_provider,
  }
}

///|
/// AI SDK-style camel-case spelling for `custom_provider`.
pub fn customProvider(
  provider_name? : String = "custom",
  language_models? : Map[String, &@provider.LanguageModelV4] = Map([]),
  completion_models? : Map[String, &@provider.CompletionModel] = Map([]),
  embedding_models? : Map[String, &@provider.EmbeddingModelV4] = Map([]),
  reranking_models? : Map[String, &@provider.RerankingModel] = Map([]),
  image_models? : Map[String, &@provider.ImageModelV4] = Map([]),
  video_models? : Map[String, &@provider.VideoModelV4] = Map([]),
  speech_models? : Map[String, &@provider.SpeechModelV4] = Map([]),
  transcription_models? : Map[String, &@provider.TranscriptionModelV4] = Map([]),
  speech_translation_models? : Map[String, &@provider.SpeechTranslationModelV4] = Map([],
  ),
  realtime_models? : Map[String, &@provider.RealtimeModelV4] = Map([]),
  files? : &@provider.Files,
  skills? : &@provider.Skills,
  fallback_provider? : &@provider.Provider,
) -> CustomProvider raise @provider.InvalidArgumentError {
  custom_provider(
    provider_name~,
    language_models~,
    completion_models~,
    embedding_models~,
    reranking_models~,
    image_models~,
    video_models~,
    speech_models~,
    transcription_models~,
    speech_translation_models~,
    realtime_models~,
    files?,
    skills?,
    fallback_provider?,
  )
}

///|
/// Return a custom provider's configured name.
pub fn CustomProvider::name(self : CustomProvider) -> String {
  self.provider_name
}

///|
/// Look up a custom or fallback language model and raise a typed model error when
/// neither side exposes it.
pub fn CustomProvider::require_language_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.LanguageModelV4 raise {
  match self.language_model(model_id) {
    Some(model) => model
    None =>
      raise @model.NoSuchModelError(
        model_id=@model.ModelId::new(provider=self.provider_name, model_id~),
        model_type=@model.Chat,
      )
  }
}

///|
/// Look up a custom or fallback embedding model and raise a typed model error.
pub fn CustomProvider::require_embedding_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.EmbeddingModelV4 raise {
  match self.embedding_model(model_id) {
    Some(model) => model
    None =>
      raise @model.NoSuchModelError(
        model_id=@model.ModelId::new(provider=self.provider_name, model_id~),
        model_type=@model.Embedding,
      )
  }
}

///|
/// Look up a custom or fallback image model and raise a typed model error.
pub fn CustomProvider::require_image_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.ImageModelV4 raise {
  match self.image_model(model_id) {
    Some(model) => model
    None =>
      raise @model.NoSuchModelError(
        model_id=@model.ModelId::new(provider=self.provider_name, model_id~),
        model_type=@model.Image,
      )
  }
}

///|
/// Look up a custom or fallback completion model and raise a typed model error.
pub fn CustomProvider::require_completion_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.CompletionModel raise {
  match self.completion_model_or_fallback(model_id) {
    Some(model) => model
    None =>
      raise @model.NoSuchModelError(
        model_id=@model.ModelId::new(provider=self.provider_name, model_id~),
        model_type=@model.Completion,
      )
  }
}

///|
/// Look up a custom or fallback reranking model and raise a typed model error.
pub fn CustomProvider::require_reranking_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.RerankingModel raise {
  match self.reranking_model_or_fallback(model_id) {
    Some(model) => model
    None =>
      raise @model.NoSuchModelError(
        model_id=@model.ModelId::new(provider=self.provider_name, model_id~),
        model_type=@model.Reranking,
      )
  }
}

///|
/// Look up a custom or fallback video model and raise a typed model error.
pub fn CustomProvider::require_video_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.VideoModelV4 raise {
  match self.video_model_or_fallback(model_id) {
    Some(model) => model
    None =>
      raise @model.NoSuchModelError(
        model_id=@model.ModelId::new(provider=self.provider_name, model_id~),
        model_type=@model.Video,
      )
  }
}

///|
/// Look up a custom or fallback speech model and raise a typed model error.
pub fn CustomProvider::require_speech_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.SpeechModelV4 raise {
  match self.speech_model_or_fallback(model_id) {
    Some(model) => model
    None =>
      raise @model.NoSuchModelError(
        model_id=@model.ModelId::new(provider=self.provider_name, model_id~),
        model_type=@model.Speech,
      )
  }
}

///|
/// Look up a custom or fallback transcription model and raise a typed model
/// error.
pub fn CustomProvider::require_transcription_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.TranscriptionModelV4 raise {
  match self.transcription_model_or_fallback(model_id) {
    Some(model) => model
    None =>
      raise @model.NoSuchModelError(
        model_id=@model.ModelId::new(provider=self.provider_name, model_id~),
        model_type=@model.Transcription,
      )
  }
}

///|
/// Look up a custom or fallback speech-translation model and raise a typed
/// model error.
pub fn CustomProvider::require_speech_translation_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.SpeechTranslationModelV4 raise {
  match self.speech_translation_model_or_fallback(model_id) {
    Some(model) => model
    None =>
      raise @model.NoSuchModelError(
        model_id=@model.ModelId::new(provider=self.provider_name, model_id~),
        model_type=@model.SpeechTranslation,
      )
  }
}

///|
/// Look up a custom or fallback realtime model and raise a typed model error.
pub fn CustomProvider::require_realtime_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.RealtimeModelV4 raise {
  match self.realtime_model_or_fallback(model_id) {
    Some(model) => model
    None =>
      raise @model.NoSuchModelError(
        model_id=@model.ModelId::new(provider=self.provider_name, model_id~),
        model_type=@model.Realtime,
      )
  }
}

///|
/// Resolve a model map before consulting the fallback provider.
fn CustomProvider::language_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.LanguageModelV4? raise {
  match self.language_models.get(model_id) {
    Some(model) => Some(model)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.language_model(model_id)
        None => None
      }
  }
}

///|
fn CustomProvider::completion_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.CompletionModel? raise {
  match self.completion_models.get(model_id) {
    Some(model) => Some(model)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.completion_model(model_id)
        None => None
      }
  }
}

///|
fn CustomProvider::embedding_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.EmbeddingModelV4? raise {
  match self.embedding_models.get(model_id) {
    Some(model) => Some(model)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.embedding_model(model_id)
        None => None
      }
  }
}

///|
fn CustomProvider::reranking_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.RerankingModel? raise {
  match self.reranking_models.get(model_id) {
    Some(model) => Some(model)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.reranking_model(model_id)
        None => None
      }
  }
}

///|
fn CustomProvider::image_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.ImageModelV4? raise {
  match self.image_models.get(model_id) {
    Some(model) => Some(model)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.image_model(model_id)
        None => None
      }
  }
}

///|
fn CustomProvider::video_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.VideoModelV4? raise {
  match self.video_models.get(model_id) {
    Some(model) => Some(model)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.video_model(model_id)
        None => None
      }
  }
}

///|
fn CustomProvider::speech_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.SpeechModelV4? raise {
  match self.speech_models.get(model_id) {
    Some(model) => Some(model)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.speech_model(model_id)
        None => None
      }
  }
}

///|
fn CustomProvider::transcription_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.TranscriptionModelV4? raise {
  match self.transcription_models.get(model_id) {
    Some(model) => Some(model)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.transcription_model(model_id)
        None => None
      }
  }
}

///|
fn CustomProvider::speech_translation_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.SpeechTranslationModelV4? raise {
  match self.speech_translation_models.get(model_id) {
    Some(model) => Some(model)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.speech_translation_model(model_id)
        None => None
      }
  }
}

///|
fn CustomProvider::realtime_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.RealtimeModelV4? raise {
  match self.realtime_models.get(model_id) {
    Some(model) => Some(model)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.realtime_model(model_id)
        None => None
      }
  }
}

///|
/// Implement the provider factory contract used by high-level AI APIs.
pub impl @provider.Provider for CustomProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.Provider for CustomProvider with fn provider_name(self) -> String {
  self.provider_name
}

///|
pub impl @provider.Provider for CustomProvider with fn language_model(
  self,
  model_id,
) {
  self.language_model_or_fallback(model_id)
}

///|
pub impl @provider.Provider for CustomProvider with fn completion_model(
  self,
  model_id,
) {
  self.completion_model_or_fallback(model_id)
}

///|
pub impl @provider.Provider for CustomProvider with fn embedding_model(
  self,
  model_id,
) {
  self.embedding_model_or_fallback(model_id)
}

///|
pub impl @provider.Provider for CustomProvider with fn reranking_model(
  self,
  model_id,
) {
  self.reranking_model_or_fallback(model_id)
}

///|
pub impl @provider.Provider for CustomProvider with fn image_model(
  self,
  model_id,
) {
  self.image_model_or_fallback(model_id)
}

///|
pub impl @provider.Provider for CustomProvider with fn video_model(
  self,
  model_id,
) {
  self.video_model_or_fallback(model_id)
}

///|
pub impl @provider.Provider for CustomProvider with fn speech_model(
  self,
  model_id,
) {
  self.speech_model_or_fallback(model_id)
}

///|
pub impl @provider.Provider for CustomProvider with fn transcription_model(
  self,
  model_id,
) {
  self.transcription_model_or_fallback(model_id)
}

///|
pub impl @provider.Provider for CustomProvider with fn speech_translation_model(
  self,
  model_id,
) {
  self.speech_translation_model_or_fallback(model_id)
}

///|
pub impl @provider.Provider for CustomProvider with fn realtime_model(
  self,
  model_id,
) {
  self.realtime_model_or_fallback(model_id)
}

///|
pub impl @provider.Provider for CustomProvider with fn files(self) {
  match self.files_service {
    Some(files) => Some(files)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.files()
        None => None
      }
  }
}

///|
pub impl @provider.Provider for CustomProvider with fn skills(self) {
  match self.skills_service {
    Some(skills) => Some(skills)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.skills()
        None => None
      }
  }
}
