///|
async fn passthrough_v4_generate(
  context : @provider.LanguageModelV4MiddlewareContext,
) -> @provider.LanguageModelV4GenerateResult {
  context.generate()
}

///|
async fn passthrough_v4_stream(
  context : @provider.LanguageModelV4MiddlewareContext,
) -> @provider.LanguageModelV4StreamResult {
  context.stream()
}

///|
async fn count_v4_transform(
  context : @provider.LanguageModelV4TransformContext,
) -> @provider.LanguageModelV4CallOptions {
  @async.pause()
  context.params
}

///|
async test "V4 middleware overrides identity and delegates generation" {
  let base = @testing.MockChatModel::new(
    [],
    @provider.ChatResponse::new(
      "ok",
      "",
      [],
      @provider.Usage::zero(),
      @provider.Stop,
    ),
    provider_name="base",
    model_id="base-model",
  )
  let model = as_language_model_v4(base)
  let wrapped = wrap_language_model_v4(
    model,
    @provider.LanguageModelV4Middleware::new(
      wrap_generate=passthrough_v4_generate,
    ),
    provider_id="wrapped",
    model_id="wrapped-model",
  )
  assert_eq(wrapped.specification_version(), "v4")
  assert_eq(wrapped.provider(), "wrapped")
  assert_eq(wrapped.model_id(), "wrapped-model")
  ignore(
    wrapped.do_generate(
      @provider.LanguageModelV4CallOptions::from_language_model_prompt([
        @provider.LanguageModelMessage::user("hello"),
      ]),
    ),
  )
  assert_eq(base.captured_messages().length(), 1)
}

///|
async test "V4 middleware delegates streaming callbacks" {
  let base = @testing.MockChatModel::new(
    [@provider.TextDelta(id="text-0", delta="ok")],
    @provider.ChatResponse::new(
      "ok",
      "",
      [],
      @provider.Usage::zero(),
      @provider.Stop,
    ),
  )
  let model = as_language_model_v4(base)
  let wrapped = wrap_language_model_v4(
    model,
    @provider.LanguageModelV4Middleware::new(wrap_stream=passthrough_v4_stream),
  )
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  ignore(
    wrapped.do_stream(
      @provider.LanguageModelV4CallOptions::from_language_model_prompt([
        @provider.LanguageModelMessage::user("hello"),
      ]),
      event => events.push(event),
    ),
  )
  assert_eq(events.length(), 3)
  assert_true(events[0] is @provider.V4StreamStart(warnings=[]))
  assert_true(events[1] is @provider.V4TextDelta(id="text-0", delta="ok", ..))
  assert_true(events[2] is @provider.V4Finish(..))
}

///|
async test "V4 middleware transforms both operations" {
  let base = @testing.MockChatModel::new(
    [@provider.TextDelta(id="text-0", delta="ok")],
    @provider.ChatResponse::new(
      "ok",
      "",
      [],
      @provider.Usage::zero(),
      @provider.Stop,
    ),
  )
  let model = as_language_model_v4(base)
  let wrapped = wrap_language_model_v4(
    model,
    @provider.LanguageModelV4Middleware::new(
      transform_params=count_v4_transform,
    ),
  )
  let options = @provider.LanguageModelV4CallOptions::from_language_model_prompt([
      @provider.LanguageModelMessage::user("hello"),
    ],
  )
  ignore(wrapped.do_generate(options))
  ignore(wrapped.do_stream(options, _ => ()))
}

///|
async test "V4 middleware chain keeps the first wrapper outermost" {
  let base = @testing.MockChatModel::new(
    [],
    @provider.ChatResponse::new(
      "ok",
      "",
      [],
      @provider.Usage::zero(),
      @provider.Stop,
    ),
  )
  let model = as_language_model_v4(base)
  let wrapped = wrap_language_model_v4_chain(model, [
    @provider.LanguageModelV4Middleware::new(override_provider=_ => "outer"),
    @provider.LanguageModelV4Middleware::new(override_model_id=_ => {
      "inner-model"
    }),
  ])
  assert_eq(wrapped.provider(), "outer")
  assert_eq(wrapped.model_id(), "inner-model")
}
