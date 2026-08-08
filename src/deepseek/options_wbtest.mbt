///|
test "DeepSeek reports unsupported topK" {
  let prepared = prepare_deepseek_request(
    "deepseek-chat",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      top_k=40.0,
    ),
    "deepseek.chat",
    false,
    true,
    false,
  )
  assert_eq(prepared.warnings.length(), 1)
  assert_true(prepared.warnings[0] is @provider.Unsupported(feature="topK", ..))
  assert_false(prepared.body.stringify().contains("top_k"))
}

///|
test "DeepSeek reports lossy top-level reasoning mappings" {
  let minimal = prepare_deepseek_request(
    "deepseek-reasoner",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      reasoning_effort=@provider.Minimal,
    ),
    "deepseek.chat",
    false,
    true,
    false,
  )
  json_inspect(minimal.body, content={
    "model": "deepseek-reasoner",
    "messages": [{ "role": "user", "content": "hello" }],
    "thinking": { "type": "enabled" },
    "reasoning_effort": "low",
  })
  assert_true(
    minimal.warnings.any(warning => {
      warning
      is @provider.Compatibility(
        feature="reasoning",
        details="reasoning \"minimal\" is not directly supported by this model. mapped to effort \"low\"."
      )
    }),
  )
  let xhigh = prepare_deepseek_request(
    "deepseek-reasoner",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      reasoning_effort=@provider.XHigh,
    ),
    "deepseek.chat",
    false,
    true,
    false,
  )
  assert_true(xhigh.body.stringify().contains("\"reasoning_effort\":\"max\""))
  assert_true(
    xhigh.warnings.any(warning => {
      warning
      is @provider.Compatibility(
        feature="reasoning",
        details="reasoning \"xhigh\" is not directly supported by this model. mapped to effort \"max\"."
      )
    }),
  )
}

///|
test "DeepSeek keeps text content wrapped in provider options" {
  let text = @provider.LanguageModelContentPart::text("cached text").with_provider_options({
      "deepseek": { "cacheControl": { "type": "ephemeral" } },
    },
  )
  let prepared = prepare_deepseek_request(
    "deepseek-chat",
    @provider.ChatCallOptions::new([
      @provider.LanguageModelMessage::user_parts([text]),
    ]),
    "deepseek.chat",
    false,
    true,
    false,
  )
  json_inspect(prepared.body, content={
    "model": "deepseek-chat",
    "messages": [{ "role": "user", "content": "cached text" }],
  })
  assert_false(
    prepared.warnings.any(warning => {
      warning is @provider.Unsupported(feature="multimodal message part", ..)
    }),
  )
}

///|
test "DeepSeek validates typed and untyped provider options" {
  try DeepSeekLanguageModelChatOptions::new(thinking_type="invalid") catch {
    Failure::Failure(message) => assert_true(message.contains("thinking_type"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected invalid thinking type to fail")
  }
  try DeepSeekLanguageModelChatOptions::new(reasoning_effort="extreme") catch {
    Failure::Failure(message) =>
      assert_true(message.contains("reasoning_effort"))
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected invalid reasoning effort to fail")
  }
  let prepared = prepare_deepseek_request(
    "deepseek-chat",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      provider_options={
        "deepseek": {
          "thinking": { "type": "invalid" },
          "reasoningEffort": "extreme",
          "strictJsonSchema": "yes",
        },
      },
    ),
    "deepseek.beta.chat",
    false,
    true,
    true,
  )
  assert_eq(prepared.warnings.length(), 3)
  assert_false(prepared.body.stringify().contains("thinking"))
  assert_false(prepared.body.stringify().contains("reasoning_effort"))
}

///|
test "DeepSeek public factories expose AI SDK model contracts" {
  let provider = createDeepSeek(api_key="test-key")
  let generic_provider = provider as &@provider.ProviderV4
  assert_eq(generic_provider.specification_version(), "v4")
  let language_model = provider.languageModel("deepseek-chat")
  assert_eq(language_model.specification_version(), "v4")
  assert_eq(language_model.provider(), "deepseek.chat")
  assert_eq(language_model.model_id(), "deepseek-chat")
  assert_eq(provider.chat("deepseek-reasoner").model_id(), "deepseek-reasoner")
  assert_true(generic_provider.reranking_model("missing") is None)
  assert_true(generic_provider.speech_model("missing") is None)
  assert_true(generic_provider.transcription_model("missing") is None)
  assert_true(generic_provider.files() is None)
  assert_true(generic_provider.skills() is None)
  try generic_provider.embedding_model("missing") catch {
    @provider.NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id, "missing")
      assert_eq(model_type, @provider.EmbeddingModel)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected DeepSeek embedding model rejection")
  }
  try generic_provider.image_model("missing") catch {
    @provider.NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id, "missing")
      assert_eq(model_type, @provider.ImageModel)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected DeepSeek image model rejection")
  }
}
