///|
test "Open Responses reports reasoning coercion and protected options" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[@provider.V4PromptText(text="hello", provider_options=Map([]))],
        provider_options=Map([]),
      ),
    ]),
    reasoning=@provider.V4ReasoningMinimal,
    top_k=40.0,
    provider_options={ "localTest": { "stream": false } },
  )
  let warnings = prepare_open_responses_v4_request(
      "test-model", options, "local-test", true,
    ).warnings
  assert_eq(warnings.length(), 3)
  assert_true(
    warnings[0] is @provider.Compatibility(feature="providerOptions.stream", ..),
  )
  assert_true(warnings[1] is @provider.Unsupported(feature="topK", ..))
  assert_eq(
    warnings[2],
    @provider.Compatibility(
      feature="reasoning",
      details="reasoning \"minimal\" is not directly supported by this model. mapped to effort \"low\".",
    ),
  )
}

///|
test "Open Responses preserves its endpoint and appends a user agent suffix" {
  let model = create_open_responses(
    provider_name="local",
    url="https://example.com/v1/responses/",
    headers={ "User-Agent": "moon-app/1.0" },
  ).responses_wire("test-model")
  assert_eq(model.url, "https://example.com/v1/responses/")
  assert_eq(
    model.request_headers().get("user-agent"),
    Some("moon-app/1.0 moonai/open-responses/0.1.0"),
  )
}

///|
test "Open Responses uses the exact configured provider options namespace" {
  let prepared = prepare_open_responses_v4_request(
    "test-model",
    @provider.LanguageModelV4CallOptions::from_language_model_prompt(
      [@provider.LanguageModelMessage::user("hello")],
      provider_options={ "local.responses": { "reasoningSummary": "auto" } },
    ),
    "local.responses",
    false,
  )
  assert_eq(prepared.warnings, [])
  assert_true(prepared.body is { "reasoning": { "summary": "auto", .. }, .. })
}

///|
test "Open Responses public factory exposes the AI SDK provider contract" {
  let provider = createOpenResponses(
    name="local",
    url="https://example.test/v1/responses",
    api_key="test-key",
  )
  let generic_provider = provider as &@provider.ProviderV4
  assert_eq(generic_provider.specification_version(), "v4")
  let language_model = provider.languageModel("test-model")
  assert_eq(language_model.specification_version(), "v4")
  assert_eq(language_model.provider(), "local.responses")
  assert_eq(language_model.model_id(), "test-model")
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
    _ => fail("expected Open Responses embedding model rejection")
  }
  try generic_provider.image_model("missing") catch {
    @provider.NoSuchModelError(model_id~, model_type~) => {
      assert_eq(model_id, "missing")
      assert_eq(model_type, @provider.ImageModel)
    }
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected Open Responses image model rejection")
  }
}

///|
test "Open Responses typed reasoning summaries cover every wire value" {
  json_inspect(
    OpenResponsesLanguageModelOptions::new(
      reasoning_summary=ReasoningSummaryConcise,
    ).to_provider_options(provider_name="local"),
    content={ "local": { "reasoningSummary": "concise" } },
  )
  json_inspect(
    OpenResponsesLanguageModelOptions::new(
      reasoning_summary=ReasoningSummaryAuto,
    ).to_provider_options(provider_name="local"),
    content={ "local": { "reasoningSummary": "auto" } },
  )
}
