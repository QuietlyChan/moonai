///|
test "Open Responses reports reasoning coercion and protected options" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    reasoning_effort=@provider.Minimal,
    top_k=40.0,
    provider_options={ "localTest": { "stream": false } },
  )
  let warnings = prepare_open_responses_request(
      "test-model", options, "local-test.responses", true,
    ).warnings
  assert_eq(warnings.length(), 3)
  assert_true(
    warnings[0] is @provider.Compatibility(feature="providerOptions.stream", ..),
  )
  assert_true(warnings[1] is @provider.Unsupported(feature="topK", ..))
  assert_true(
    warnings[2] is @provider.Compatibility(feature="reasoningEffort", ..),
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
test "Open Responses skips unsupported tool-result content with warnings" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::tool_parts("call-1", [
      @provider.LanguageModelContentPart::file_reference(
        reference=@provider.ProviderReference::single(
          provider="other",
          id="file-1",
        ),
        media_type="application/pdf",
      ),
      @provider.LanguageModelContentPart::audio_data(
        data="YXVkaW8=",
        format="wav",
      ),
      @provider.LanguageModelContentPart::text("kept"),
    ]),
  ])
  let prepared = prepare_open_responses_request(
    "model", options, "open-responses.responses", false,
  )
  json_inspect(prepared.body, content={
    "model": "model",
    "input": [
      {
        "type": "function_call_output",
        "call_id": "call-1",
        "output": [{ "type": "input_text", "text": "kept" }],
      },
    ],
  })
  assert_eq(prepared.warnings, [
    @provider.Other(
      message="unsupported tool content part type: file with data type: reference",
    ),
    @provider.Other(message="unsupported tool content part type: audio"),
  ])
}

///|
test "Open Responses unwraps provider options before classifying content" {
  let part_options : Map[String, Json] = {
    "openResponses": { "cacheControl": { "type": "ephemeral" } },
  }
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::system("ignored"),
    @provider.LanguageModelMessage::assistant_parts([
      @provider.LanguageModelContentPart::text("prior").with_provider_options(
        part_options,
      ),
    ]),
    @provider.LanguageModelMessage::tool_parts("call-1", [
      @provider.LanguageModelContentPart::file_reference(
        reference=@provider.ProviderReference::single(
          provider="other",
          id="file-1",
        ),
      ).with_provider_options(part_options),
      @provider.LanguageModelContentPart::audio_data(
        data="YXVkaW8=",
        format="wav",
      ).with_provider_options(part_options),
      @provider.LanguageModelContentPart::text("kept").with_provider_options(
        part_options,
      ),
    ]),
  ])
  let prepared = prepare_open_responses_request(
    "model", options, "open-responses.responses", false,
  )
  json_inspect(prepared.body, content={
    "model": "model",
    "input": [
      {
        "type": "message",
        "role": "assistant",
        "content": [{ "type": "output_text", "text": "prior" }],
      },
      {
        "type": "function_call_output",
        "call_id": "call-1",
        "output": [{ "type": "input_text", "text": "kept" }],
      },
    ],
    "instructions": "ignored",
  })
  assert_eq(prepared.warnings, [
    @provider.Other(
      message="unsupported tool content part type: file with data type: reference",
    ),
    @provider.Other(message="unsupported tool content part type: audio"),
  ])
}
