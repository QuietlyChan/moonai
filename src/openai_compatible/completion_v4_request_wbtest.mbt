///|
test "compatible completion V4 preserves extension options directly" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[@provider.V4PromptText(text="Hello", provider_options=Map([]))],
        provider_options=Map([]),
      ),
    ]),
    max_output_tokens=32,
    top_k=10.0,
    stop_sequences=["DONE"],
    provider_options={
      "acme": { "suffix": "!", "logitBias": { "7": -1 }, "vendorFlag": true },
    },
  )
  let prepared = prepare_compatible_completion_v4_request(
    "completion-model", options, "acme", true, true,
  )
  json_inspect(prepared.body, content={
    "model": "completion-model",
    "prompt": "user:\nHello\n\nassistant:\n",
    "stream": true,
    "stream_options": { "include_usage": true },
    "max_tokens": 32,
    "stop": ["\nuser:", "DONE"],
    "suffix": "!",
    "logit_bias": { "7": -1 },
    "vendorFlag": true,
  })
  assert_eq(prepared.warnings.length(), 1)
  assert_true(prepared.warnings[0] is @provider.Unsupported(feature="topK", ..))
}
