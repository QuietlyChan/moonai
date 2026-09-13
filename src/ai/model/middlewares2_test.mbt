///|
priv struct CapturingV4Model {
  captured_options : Ref[@provider.LanguageModelV4CallOptions?]
  stream_events : Array[@provider.LanguageModelV4StreamPart]
}

///|
fn CapturingV4Model::new(
  stream_events? : Array[@provider.LanguageModelV4StreamPart] = [],
) -> CapturingV4Model {
  { captured_options: Ref(None), stream_events, }
}

///|
impl @provider.LanguageModelV4 for CapturingV4Model with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for CapturingV4Model with fn provider(_self) -> String {
  "test.capture"
}

///|
impl @provider.LanguageModelV4 for CapturingV4Model with fn model_id(_self) -> String {
  "capture-model"
}

///|
impl @provider.LanguageModelV4 for CapturingV4Model with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
impl @provider.LanguageModelV4 for CapturingV4Model with fn do_generate(
  self,
  options,
) {
  self.captured_options.val = Some(options)
  {
    content: [@provider.LanguageModelV4Content::text("raw")],
    finish_reason: { unified: @provider.V4FinishStop, raw: None, },
    usage: @provider.LanguageModelV4Usage::unknown(),
    warnings: [],
    provider_metadata: Map([]),
    request: None,
    response: None,
  }
}

///|
impl @provider.LanguageModelV4 for CapturingV4Model with fn do_stream(
  self,
  options,
  on_event,
) {
  self.captured_options.val = Some(options)
  for event in self.stream_events {
    on_event(event)
  }
  @provider.LanguageModelV4StreamResult::new(None, None)
}

///|
fn capture_call_options() -> @provider.LanguageModelV4CallOptions {
  @provider.LanguageModelV4CallOptions::from_language_model_prompt([
    @provider.LanguageModelMessage::user("hi"),
  ])
}

///|
async test "default instructions middleware injects a system message" {
  let model = CapturingV4Model::new()
  let wrapped = wrap_language_model_v4(
    model as &@provider.LanguageModelV4,
    default_instructions_middleware(
      instructions=@prompt.InstructionText("You are helpful."),
    ),
  )
  ignore(wrapped.do_stream(capture_call_options(), _ => ()))
  let options = model.captured_options.val.unwrap()
  assert_eq(options.prompt.messages.length(), 2)
  assert_true(
    options.prompt.messages[0]
    is @provider.V4SystemMessage(content="You are helpful.", ..),
  )
}

///|
async test "default instructions middleware keeps existing system messages" {
  let model = CapturingV4Model::new()
  let wrapped = wrap_language_model_v4(
    model as &@provider.LanguageModelV4,
    default_instructions_middleware(
      instructions=@prompt.InstructionText("You are helpful."),
    ),
  )
  let options_with_system = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4SystemMessage(content="existing", provider_options=Map([])),
      @provider.V4UserMessage(
        content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
        provider_options=Map([]),
      ),
    ]),
  )
  ignore(wrapped.do_stream(options_with_system, _ => ()))
  let options = model.captured_options.val.unwrap()
  assert_eq(options.prompt.messages.length(), 2)
  assert_true(
    options.prompt.messages[0]
    is @provider.V4SystemMessage(content="existing", ..),
  )
}

///|
async test "add tool input examples middleware appends to descriptions" {
  let model = CapturingV4Model::new()
  let wrapped = wrap_language_model_v4(
    model as &@provider.LanguageModelV4,
    add_tool_input_examples_middleware(),
  )
  let tool = @provider.LanguageModelV4Tool::function(
    "lookup",
    { "type": "object" },
    description="Look things up",
    input_examples=[{ "query": "moon" }, { "query": "bit" }],
  )
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([]),
    tools=[tool],
  )
  ignore(wrapped.do_stream(options, _ => ()))
  let captured = model.captured_options.val.unwrap()
  match captured.tools[0] {
    @provider.V4FunctionTool(value) => {
      assert_eq(
        value.description.unwrap(),
        "Look things up\n\nInput Examples:\n{\"query\":\"moon\"}\n{\"query\":\"bit\"}",
      )
      assert_eq(value.input_examples.length(), 0)
    }
    _ => fail("expected a function tool")
  }
}

///|
async test "add tool input examples middleware keeps examples when asked" {
  let model = CapturingV4Model::new()
  let wrapped = wrap_language_model_v4(
    model as &@provider.LanguageModelV4,
    add_tool_input_examples_middleware(prefix="Examples:", remove=false, format=fn(
      example : @provider.LanguageModelV4FunctionToolInputExample,
      _index : Int,
    ) -> String {
      "Q: \{(example.input).stringify()}"
    }),
  )
  let tool = @provider.LanguageModelV4Tool::function(
    "lookup",
    { "type": "object" },
    input_examples=[{ "query": "moon" }],
  )
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([]),
    tools=[tool],
  )
  ignore(wrapped.do_stream(options, _ => ()))
  let captured = model.captured_options.val.unwrap()
  match captured.tools[0] {
    @provider.V4FunctionTool(value) => {
      assert_eq(
        value.description.unwrap(),
        "Examples:\nQ: {\"query\":\"moon\"}",
      )
      assert_eq(value.input_examples.length(), 1)
    }
    _ => fail("expected a function tool")
  }
}

///|
async test "extract json middleware transforms generate output" {
  let model = CapturingV4Model::new()
  let wrapped = wrap_language_model_v4(
    model as &@provider.LanguageModelV4,
    extract_json_middleware(),
  )
  let result = wrapped.do_generate(capture_call_options())
  match result.content[0] {
    @provider.V4TextOutput(value) => assert_eq(value.text, "raw".to_string())
    _ => fail("expected text content")
  }
  ignore(model)
}

///|
async test "extract json middleware strips fences across stream deltas" {
  let model = CapturingV4Model::new(stream_events=[
    @provider.V4TextStart(id="t0", provider_metadata=Map([])),
    @provider.V4TextDelta(id="t0", delta="```json\n", provider_metadata=Map([])),
    @provider.V4TextDelta(id="t0", delta="{\"a\":1", provider_metadata=Map([])),
    @provider.V4TextDelta(id="t0", delta="}\n```", provider_metadata=Map([])),
    @provider.V4TextEnd(id="t0", provider_metadata=Map([])),
  ])
  let wrapped = wrap_language_model_v4(
    model as &@provider.LanguageModelV4,
    extract_json_middleware(),
  )
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  ignore(wrapped.do_stream(capture_call_options(), event => events.push(event)))
  let deltas = StringBuilder()
  for event in events {
    match event {
      @provider.V4TextDelta(delta~, ..) => deltas.write_string(delta)
      _ => ()
    }
  }
  assert_eq(deltas.to_string(), "{\"a\":1}")
  // The stream still starts and ends the text block exactly once.
  assert_true(events[0] is @provider.V4TextStart(..))
  assert_true(events[events.length() - 1] is @provider.V4TextEnd(..))
}

///|
async test "extract json middleware passes plain text through" {
  let model = CapturingV4Model::new(stream_events=[
    @provider.V4TextStart(id="t0", provider_metadata=Map([])),
    @provider.V4TextDelta(
      id="t0",
      delta="plain answer",
      provider_metadata=Map([]),
    ),
    @provider.V4TextEnd(id="t0", provider_metadata=Map([])),
  ])
  let wrapped = wrap_language_model_v4(
    model as &@provider.LanguageModelV4,
    extract_json_middleware(),
  )
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  ignore(wrapped.do_stream(capture_call_options(), event => events.push(event)))
  let deltas = StringBuilder()
  for event in events {
    match event {
      @provider.V4TextDelta(delta~, ..) => deltas.write_string(delta)
      _ => ()
    }
  }
  assert_eq(deltas.to_string(), "plain answer")
}

///|
async test "default embedding settings middleware fills unset fields" {
  let middleware = default_embedding_settings_middleware(
    headers=Map([("X-Default", "yes")]),
    provider_options={ "openai": { "dimensions": 256 } },
  )
  let transform = middleware.transform_params.unwrap()
  let model = @testing.MockEmbeddingModel::new(
    @provider.EmbeddingBatchResponse::new(
      [[0.1]],
      @provider.Usage::new(input_tokens=1, output_tokens=0),
    ),
  )
  let params = @provider.EmbeddingModelV4CallOptions::new(
    ["hi"],
    headers=Map([("X-Call", "kept")]),
  )
  let merged = transform(params, model as &@provider.EmbeddingModelV4)
  assert_eq(merged.headers.get("X-Call"), Some("kept"))
  assert_eq(merged.headers.get("X-Default"), Some("yes"))
  assert_true(merged.provider_options.get("openai") is Some(_))
}
