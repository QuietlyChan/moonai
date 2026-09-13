///|
test "google model path prefixes bare ids with models/" {
  assert_eq(get_model_path("gemini-2.5-pro"), "models/gemini-2.5-pro")
  assert_eq(get_model_path("tunedModels/my-model"), "tunedModels/my-model")
}

///|
test "google finish reason mapping covers gemini raw values" {
  assert_eq(google_map_finish_reason(Some("STOP")), {
    unified: @provider.V4FinishStop,
    raw: Some("STOP"),
  })
  assert_eq(google_map_finish_reason(Some("SAFETY")), {
    unified: @provider.V4FinishContentFilter,
    raw: Some("SAFETY"),
  })
  assert_eq(google_map_finish_reason(Some("MALFORMED_FUNCTION_CALL")), {
    unified: @provider.V4FinishError,
    raw: Some("MALFORMED_FUNCTION_CALL"),
  })
}

///|
test "google usage splits thought tokens out of output" {
  let usage = google_usage(
    Some({
      "promptTokenCount": 10,
      "candidatesTokenCount": 30,
      "thoughtsTokenCount": 12,
    }),
  )
  assert_eq(usage.input_tokens.total, Some(10))
  assert_eq(usage.output_tokens.total, Some(30))
  assert_eq(usage.output_tokens.reasoning, Some(12))
  assert_eq(usage.output_tokens.text, Some(18))
}

///|
test "google parts decode text reasoning and function calls" {
  let content = google_parts_to_content(
    [
      { "text": "answer" },
      { "text": "pondering", "thought": true },
      { "functionCall": { "name": "lookup", "args": { "q": "x" } } },
    ],
    @provider_utils.generate_id,
  )
  assert_eq(content.length(), 3)
  assert_true(content[0] is @provider.V4TextOutput(_))
  assert_true(content[1] is @provider.V4ReasoningOutput(_))
  assert_true(content[2] is @provider.V4ToolCallOutput(_))
}

///|
test "google message conversion merges system and maps roles" {
  let prompt = @provider.LanguageModelV4Prompt::new([
    @provider.V4SystemMessage(content="be terse", provider_options=Map([])),
    @provider.V4UserMessage(
      content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
      provider_options=Map([]),
    ),
  ])
  let (contents, system) = google_convert_messages(prompt)
  assert_eq(system, "be terse")
  assert_eq(contents.length(), 1)
  assert_true(contents[0] is { "role": "user", .. })
}
