///|
test "typed OpenAI Completion options override normalized suffix fallback" {
  let call_options = @provider.CompletionOptions::new(
    "MoonBit is",
    suffix="standard suffix",
    provider_options=OpenAILanguageModelCompletionOptions::new(
      echo=true,
      logit_bias={ "42": -1.5 },
      suffix="provider suffix",
      user="typed-user",
      logprobs=OpenAILogprobs::enabled(),
    ).to_provider_options(),
  )
  let parsed = parse_openai_completion_options(
    call_options, "openai.completion",
  )
  json_inspect(
    openai_completion_request(
      "gpt-3.5-turbo-instruct",
      call_options,
      parsed.options,
      false,
      true,
    ),
    content={
      "model": "gpt-3.5-turbo-instruct",
      "prompt": "MoonBit is",
      "suffix": "provider suffix",
      "echo": true,
      "logit_bias": { "42": -1.5 },
      "logprobs": 0,
      "user": "typed-user",
    },
  )
}

///|
test "typed OpenAI embedding options override normalized fallbacks" {
  let call_options = @provider.EmbeddingOptions::new(
    dimensions=256,
    user="standard-user",
    provider_options=OpenAIEmbeddingModelOptions::new(
      dimensions=64,
      user="typed-user",
    ).to_provider_options(),
  )
  let parsed = parse_openai_embedding_options(call_options, "openai.embedding")
  json_inspect(
    openai_embedding_request(
      "text-embedding-3-small",
      ["hello"],
      call_options,
      parsed.options,
    ),
    content={
      "model": "text-embedding-3-small",
      "input": ["hello"],
      "encoding_format": "float",
      "dimensions": 64,
      "user": "typed-user",
    },
  )
}

///|
test "typed OpenAI image generation and edit options reach the parser" {
  let generation_call = @provider.ImageCallOptions::new(
    "A MoonBit logo",
    provider_options=OpenAIImageModelGenerationOptions::new(
      quality=OpenAIImageQualityHigh,
      background=OpenAIImageBackgroundTransparent,
      output_format=OpenAIImageOutputWebp,
      output_compression=80,
      user="typed-user",
      style=OpenAIImageStyleNatural,
      moderation=OpenAIImageModerationLow,
    ).to_provider_options(),
  )
  let generation = parse_openai_image_options(generation_call, "openai.image")
  json_inspect(
    openai_image_generation_body(
      "gpt-image-1",
      generation_call,
      generation.options,
      false,
    ),
    content={
      "model": "gpt-image-1",
      "prompt": "A MoonBit logo",
      "n": 1,
      "quality": "high",
      "style": "natural",
      "background": "transparent",
      "moderation": "low",
      "output_format": "webp",
      "output_compression": 80,
      "user": "typed-user",
    },
  )
  let edit_call = @provider.ImageCallOptions::new(
    "Edit the logo",
    provider_options=OpenAIImageModelEditOptions::new(
      input_fidelity=OpenAIImageInputFidelityHigh,
    ).to_provider_options(),
  )
  let edit = parse_openai_image_options(edit_call, "openai.image")
  assert_eq(edit.options.input_fidelity, Some("high"))
}

///|
test "typed OpenAI speech options reach the wire body" {
  let call_options = @provider.SpeechCallOptions::new(
    text="Hello MoonBit",
    provider_options=OpenAISpeechModelOptions::new(
      instructions="Speak clearly",
      speed=1.25,
    ).to_provider_options(),
  )
  let (body, format, warnings) = prepare_openai_speech_request(
    "gpt-4o-mini-tts", call_options, "openai.speech",
  )
  assert_eq(format, "mp3")
  assert_eq(warnings, [])
  json_inspect(body, content={
    "model": "gpt-4o-mini-tts",
    "input": "Hello MoonBit",
    "voice": "alloy",
    "response_format": "mp3",
    "speed": 1.25,
    "instructions": "Speak clearly",
  })
}

///|
test "typed OpenAI transcription options parse and report unsupported streaming" {
  let call_options = @provider.TranscriptionCallOptions::new(
    audio=@provider.TranscriptionAudio::bytes(b"audio"),
    media_type="audio/wav",
    provider_options=OpenAITranscriptionModelOptions::new(
      include_values=["logprobs"],
      language="en",
      prompt="MoonBit",
      temperature=0.25,
      timestamp_granularities=[
        OpenAITranscriptionWord,
        OpenAITranscriptionSegment,
      ],
      streaming=OpenAITranscriptionStreamingOptions::new(
        delay=OpenAITranscriptionDelayLow,
        include_values=["item.input_audio_transcription.logprobs"],
      ),
    ).to_provider_options(),
  )
  let parsed = parse_openai_transcription_options(
    call_options, "openai.transcription",
  )
  assert_eq(parsed.options.include_fields, ["logprobs"])
  assert_eq(parsed.options.language, Some("en"))
  assert_eq(parsed.options.prompt, Some("MoonBit"))
  assert_eq(parsed.options.temperature, Some(0.25))
  assert_eq(parsed.options.timestamp_granularities, ["word", "segment"])
  assert_eq(parsed.warnings.length(), 1)
  assert_true(
    parsed.warnings[0]
    is @provider.Unsupported(feature="providerOptions.openai.streaming", ..),
  )
}
