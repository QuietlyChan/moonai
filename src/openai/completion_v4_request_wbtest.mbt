///|
test "OpenAI completion V4 prepares the wire request directly" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4SystemMessage(content="Be concise.", provider_options=Map([])),
      @provider.V4UserMessage(
        content=[@provider.V4PromptText(text="Hello", provider_options=Map([]))],
        provider_options=Map([]),
      ),
    ]),
    max_output_tokens=64,
    temperature=0.25,
    top_k=20.0,
    stop_sequences=["END"],
    provider_options={
      "openai": {
        "suffix": "!",
        "echo": true,
        "logprobs": 2,
        "logitBias": { "42": 1.5 },
        "user": "user-1",
      },
    },
  )
  let prepared = prepare_openai_completion_v4_request(
    "gpt-3.5-turbo-instruct", options, "openai.completion", true, true,
  )
  json_inspect(prepared.body, content={
    "model": "gpt-3.5-turbo-instruct",
    "prompt": "Be concise.\n\nuser:\nHello\n\nassistant:\n",
    "stream": true,
    "stream_options": { "include_usage": true },
    "suffix": "!",
    "echo": true,
    "logit_bias": { "42": 1.5 },
    "logprobs": 2,
    "user": "user-1",
    "max_tokens": 64,
    "temperature": 0.25,
    "stop": ["\nuser:", "END"],
  })
  assert_eq(prepared.warnings.length(), 1)
  assert_true(prepared.warnings[0] is @provider.Unsupported(feature="topK", ..))
}
