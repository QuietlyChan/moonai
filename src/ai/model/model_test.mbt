///|
test "model identities use provider-qualified keys" {
  let id = ModelId::new(provider="openai", model_id="gpt-4.1")
  assert_eq(id.provider(), "openai")
  assert_eq(id.model_id(), "gpt-4.1")
  assert_eq(id.key(), "openai:gpt-4.1")
  match LanguageModelV4Reference::named(provider="openai", model_id="gpt-4.1") {
    Named(value) => assert_eq(value, id)
    Instance(_) => fail("expected a named model reference")
  }
}

///|
test "model identities parse canonical registry keys" {
  assert_eq(
    ModelId::parse(" openai:gpt-4.1 "),
    Some(ModelId::new(provider="openai", model_id="gpt-4.1")),
  )
  assert_eq(ModelId::parse("gpt-4.1"), None)
  assert_eq(ModelId::parse(":"), None)
  assert_eq(ModelId::parse("openai:"), None)
  assert_eq(
    ModelId::parse("gateway:model:version"),
    Some(ModelId::new(provider="gateway", model_id="model:version")),
  )
}

///|
test "invalid model keys raise a typed error" {
  try parse_model_id("gpt-4.1") catch {
    InvalidModelIdError(value~) => assert_eq(value, "gpt-4.1")
  } noraise {
    _ => fail("expected an invalid model id to fail")
  }
}

///|
test "registry resolves language models by their provider identity" {
  let chat = @testing.MockChatModel::new(
    [],
    @provider.ChatResponse::empty(),
    provider_name="test-provider",
    model_id="v4-model",
  )
  let v4 = as_language_model_v4(chat)
  let registry = ModelRegistry::new().with_language_model(v4)
  let id = ModelId::new(provider="test-provider", model_id="v4-model")
  assert_eq(model_id_of_language_model(v4), id)
  assert_true(registry.language_model(id) is Some(_))
  assert_true(
    registry.language_model_by_key("test-provider:v4-model") is Some(_),
  )
  assert_eq(
    registry
    .resolve_language_model(
      LanguageModelV4Reference::named(
        provider="test-provider",
        model_id="v4-model",
      ),
    )
    .model_id(),
    "v4-model",
  )
}

///|
test "registry reports missing model identity" {
  let registry = ModelRegistry::new()
  try
    registry.require_language_model(
      ModelId::new(provider="missing", model_id="model"),
    )
  catch {
    NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id.key(), "missing:model")
      assert_eq(model_type, Chat)
    }
  } noraise {
    _ => fail("expected NoSuchModelError")
  }
}

///|
test "registry resolves completion and image models" {
  let completion = @testing.MockCompletionModel::new(
    [],
    @provider.CompletionResponse::new(
      "",
      @provider.Usage::zero(),
      @provider.Stop,
    ),
    provider_name="test-provider",
    model_id="completion-model",
  )
  let image = @testing.MockImageModel::new(
    @provider.ImageResponse::new([], @provider.Usage::zero()),
    provider_name="test-provider",
    model_id="image-model",
  )
  let registry = ModelRegistry::new()
    .with_completion_model(completion)
    .with_image_model(image)
  assert_eq(
    registry
    .resolve_completion_model(
      CompletionModelReference::named(
        provider="test-provider",
        model_id="completion-model",
      ),
    )
    .model_id(),
    "completion-model",
  )
  assert_eq(
    registry
    .resolve_image_model(ImageModelReference::instance(image))
    .model_id(),
    "image-model",
  )
  assert_true(registry.image_model_by_key("invalid") is None)
}

///|
test "registry resolves reranking models by provider-qualified identity" {
  let model = @testing.MockRerankingModel::new(
    @provider.RerankingResponse::new([]),
    provider_name="test-reranker-provider",
    model_id="test-reranker",
  )
  let registry = ModelRegistry::new().with_reranking_model(model)
  let id = ModelId::new(
    provider="test-reranker-provider",
    model_id="test-reranker",
  )
  let resolved = registry.require_reranking_model(id)
  assert_eq(resolved.model_id(), "test-reranker")
  match
    RerankingModelReference::named(
      provider="test-reranker-provider",
      model_id="test-reranker",
    ) {
    Named(reference_id) =>
      assert_eq(
        registry
        .resolve_reranking_model(
          RerankingModelReference::named(
            provider="test-reranker-provider",
            model_id="test-reranker",
          ),
        )
        .model_id(),
        reference_id.model_id(),
      )
    Instance(_) => fail("expected a named reranking reference")
  }
}

///|
test "registry covers every provider model contract" {
  let embedding = @testing.MockEmbeddingModel::new(
    @provider.EmbeddingBatchResponse::new([], @provider.Usage::zero()),
    provider_name="test-provider",
    model_id="embedding-model",
  )
  let video = @testing.MockVideoModel::new(
    @provider.VideoResponse::new([]),
    provider_name="test-provider",
    model_id="video-model",
  )
  let speech = @testing.MockSpeechModel::new(
    @provider.SpeechResponse::new(
      audio=@provider.SpeechAudioData::base64(""),
      media_type="audio/mpeg",
    ),
    provider_name="test-provider",
    model_id="speech-model",
  )
  let transcription = @testing.MockTranscriptionModel::new(
    @provider.TranscriptionResponse::new(text=""),
    provider_name="test-provider",
    model_id="transcription-model",
  )
  let translation = @testing.MockSpeechTranslationModel::new(
    [],
    @provider.SpeechTranslationResponse::new(source_text="", output_text=""),
    provider_name="test-provider",
    model_id="translation-model",
  )
  let realtime = @testing.MockRealtimeModel::new(
    provider_name="test-provider",
    model_id="realtime-model",
  )
  let registry = ModelRegistry::new()
    .with_embedding_model(embedding)
    .with_video_model(video)
    .with_speech_model(speech)
    .with_transcription_model(transcription)
    .with_speech_translation_model(translation)
    .with_realtime_model(realtime)
  assert_eq(
    registry
    .resolve_embedding_model(
      EmbeddingModelReference::named(
        provider="test-provider",
        model_id="embedding-model",
      ),
    )
    .model_id(),
    "embedding-model",
  )
  assert_eq(
    registry
    .resolve_video_model(
      VideoModelReference::named(
        provider="test-provider",
        model_id="video-model",
      ),
    )
    .model_id(),
    "video-model",
  )
  assert_eq(
    registry
    .resolve_speech_model(SpeechModelReference::instance(speech))
    .model_id(),
    "speech-model",
  )
  assert_eq(
    registry
    .resolve_transcription_model(
      TranscriptionModelReference::named(
        provider="test-provider",
        model_id="transcription-model",
      ),
    )
    .model_id(),
    "transcription-model",
  )
  assert_eq(
    registry
    .resolve_speech_translation_model(
      SpeechTranslationModelReference::instance(translation),
    )
    .model_id(),
    "translation-model",
  )
  assert_eq(
    registry
    .resolve_realtime_model(
      RealtimeModelReference::named(
        provider="test-provider",
        model_id="realtime-model",
      ),
    )
    .model_id(),
    "realtime-model",
  )
  assert_true(
    registry.speech_model_by_key("test-provider:speech-model") is Some(_),
  )
  try
    registry.require_video_model(
      ModelId::new(provider="missing", model_id="video"),
    )
  catch {
    NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id.key(), "missing:video")
      assert_eq(model_type, Video)
    }
  } noraise {
    _ => fail("expected a missing video model to fail")
  }
}
