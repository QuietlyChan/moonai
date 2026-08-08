///|
/// A provider assembled from application-owned V4 model instances.
///
/// This mirrors AI SDK's `customProvider`: configured model maps take
/// precedence over the optional fallback provider.
pub struct CustomProvider {
  priv language_models : Map[String, &@provider.LanguageModelV4]
  priv embedding_models : Map[String, &@provider.EmbeddingModelV4]
  priv image_models : Map[String, &@provider.ImageModelV4]
  priv transcription_models : Map[String, &@provider.TranscriptionModelV4]
  priv speech_models : Map[String, &@provider.SpeechModelV4]
  priv reranking_models : Map[String, &@provider.RerankingModelV4]
  priv video_models : Map[String, &@provider.VideoModelV4]
  priv files_service : &@provider.FilesV4?
  priv skills_service : &@provider.SkillsV4?
  priv fallback_provider : &@provider.ProviderV4?
}

///|
/// Construct a custom provider from model maps and optional provider services.
pub fn custom_provider(
  language_models? : Map[String, &@provider.LanguageModelV4] = Map([]),
  embedding_models? : Map[String, &@provider.EmbeddingModelV4] = Map([]),
  image_models? : Map[String, &@provider.ImageModelV4] = Map([]),
  transcription_models? : Map[String, &@provider.TranscriptionModelV4] = Map([]),
  speech_models? : Map[String, &@provider.SpeechModelV4] = Map([]),
  reranking_models? : Map[String, &@provider.RerankingModelV4] = Map([]),
  video_models? : Map[String, &@provider.VideoModelV4] = Map([]),
  files? : &@provider.FilesV4,
  skills? : &@provider.SkillsV4,
  fallback_provider? : &@provider.ProviderV4,
) -> CustomProvider {
  {
    language_models,
    embedding_models,
    image_models,
    transcription_models,
    speech_models,
    reranking_models,
    video_models,
    files_service: files,
    skills_service: skills,
    fallback_provider,
  }
}

///|
/// AI SDK-style camel-case spelling for `custom_provider`.
pub fn customProvider(
  language_models? : Map[String, &@provider.LanguageModelV4] = Map([]),
  embedding_models? : Map[String, &@provider.EmbeddingModelV4] = Map([]),
  image_models? : Map[String, &@provider.ImageModelV4] = Map([]),
  transcription_models? : Map[String, &@provider.TranscriptionModelV4] = Map([]),
  speech_models? : Map[String, &@provider.SpeechModelV4] = Map([]),
  reranking_models? : Map[String, &@provider.RerankingModelV4] = Map([]),
  video_models? : Map[String, &@provider.VideoModelV4] = Map([]),
  files? : &@provider.FilesV4,
  skills? : &@provider.SkillsV4,
  fallback_provider? : &@provider.ProviderV4,
) -> CustomProvider {
  custom_provider(
    language_models~,
    embedding_models~,
    image_models~,
    transcription_models~,
    speech_models~,
    reranking_models~,
    video_models~,
    files?,
    skills?,
    fallback_provider?,
  )
}

///|
fn no_such_custom_model(
  model_id : String,
  model_type : @provider.NoSuchModelType,
) -> @provider.NoSuchModelError {
  @provider.NoSuchModelError(model_id~, model_type~)
}

///|
fn CustomProvider::language_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.LanguageModelV4? raise {
  match self.language_models.get(model_id) {
    Some(model) => Some(model)
    None =>
      match self.fallback_provider {
        Some(provider) => Some(provider.language_model(model_id))
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
        Some(provider) => Some(provider.embedding_model(model_id))
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
        Some(provider) => Some(provider.image_model(model_id))
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
fn CustomProvider::reranking_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.RerankingModelV4? raise {
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
fn CustomProvider::video_model_or_fallback(
  self : CustomProvider,
  model_id : String,
) -> &@provider.VideoModelV4? {
  self.video_models.get(model_id)
}

///|
fn CustomProvider::files_or_fallback(
  self : CustomProvider,
) -> &@provider.FilesV4? raise {
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
fn CustomProvider::skills_or_fallback(
  self : CustomProvider,
) -> &@provider.SkillsV4? raise {
  match self.skills_service {
    Some(skills) => Some(skills)
    None =>
      match self.fallback_provider {
        Some(provider) => provider.skills()
        None => None
      }
  }
}

///|
/// Resolve a configured or fallback language model.
pub fn CustomProvider::language_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.LanguageModelV4 raise {
  match self.language_model_or_fallback(model_id) {
    Some(model) => model
    None => raise no_such_custom_model(model_id, @provider.LanguageModel)
  }
}

///|
/// Resolve a configured or fallback embedding model.
pub fn CustomProvider::embedding_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.EmbeddingModelV4 raise {
  match self.embedding_model_or_fallback(model_id) {
    Some(model) => model
    None => raise no_such_custom_model(model_id, @provider.EmbeddingModel)
  }
}

///|
/// Resolve a configured or fallback image model.
pub fn CustomProvider::image_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.ImageModelV4 raise {
  match self.image_model_or_fallback(model_id) {
    Some(model) => model
    None => raise no_such_custom_model(model_id, @provider.ImageModel)
  }
}

///|
/// Resolve a configured or fallback transcription model.
pub fn CustomProvider::transcription_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.TranscriptionModelV4 raise {
  match self.transcription_model_or_fallback(model_id) {
    Some(model) => model
    None => raise no_such_custom_model(model_id, @provider.TranscriptionModel)
  }
}

///|
/// Resolve a configured or fallback speech model.
pub fn CustomProvider::speech_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.SpeechModelV4 raise {
  match self.speech_model_or_fallback(model_id) {
    Some(model) => model
    None => raise no_such_custom_model(model_id, @provider.SpeechModel)
  }
}

///|
/// Resolve a configured or fallback reranking model.
pub fn CustomProvider::reranking_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.RerankingModelV4 raise {
  match self.reranking_model_or_fallback(model_id) {
    Some(model) => model
    None => raise no_such_custom_model(model_id, @provider.RerankingModel)
  }
}

///|
/// Resolve a configured video model.
///
/// `videoModel` is an experimental structural extension in AI SDK rather than
/// part of `ProviderV4`; MoonBit therefore cannot discover it through a
/// `ProviderV4` fallback trait object.
pub fn CustomProvider::video_model(
  self : CustomProvider,
  model_id : String,
) -> &@provider.VideoModelV4 raise {
  match self.video_model_or_fallback(model_id) {
    Some(model) => model
    None => raise no_such_custom_model(model_id, @provider.VideoModel)
  }
}

///|
/// Resolve the configured or fallback file service.
pub fn CustomProvider::files(self : CustomProvider) -> &@provider.FilesV4 raise {
  match self.files_or_fallback() {
    Some(files) => files
    None =>
      raise NoSuchProviderCapabilityError(
        provider_id="custom",
        capability="files",
      )
  }
}

///|
/// Resolve the configured or fallback skill service.
pub fn CustomProvider::skills(
  self : CustomProvider,
) -> &@provider.SkillsV4 raise {
  match self.skills_or_fallback() {
    Some(skills) => skills
    None =>
      raise NoSuchProviderCapabilityError(
        provider_id="custom",
        capability="skills",
      )
  }
}

///|
pub impl @provider.ProviderV4 for CustomProvider with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ProviderV4 for CustomProvider with fn language_model(
  self,
  model_id,
) {
  CustomProvider::language_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for CustomProvider with fn embedding_model(
  self,
  model_id,
) {
  CustomProvider::embedding_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for CustomProvider with fn image_model(
  self,
  model_id,
) {
  CustomProvider::image_model(self, model_id)
}

///|
pub impl @provider.ProviderV4 for CustomProvider with fn transcription_model(
  self,
  model_id,
) {
  self.transcription_model_or_fallback(model_id)
}

///|
pub impl @provider.ProviderV4 for CustomProvider with fn speech_model(
  self,
  model_id,
) {
  self.speech_model_or_fallback(model_id)
}

///|
pub impl @provider.ProviderV4 for CustomProvider with fn reranking_model(
  self,
  model_id,
) {
  self.reranking_model_or_fallback(model_id)
}

///|
pub impl @provider.ProviderV4 for CustomProvider with fn files(self) {
  self.files_or_fallback()
}

///|
pub impl @provider.ProviderV4 for CustomProvider with fn skills(self) {
  self.skills_or_fallback()
}
