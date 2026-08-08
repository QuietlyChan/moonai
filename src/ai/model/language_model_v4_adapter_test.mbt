///|
async test "ChatModel can be adapted to the V4 contract" {
  let expected = @provider.ChatResponse::new(
    "hello",
    "",
    [],
    @provider.Usage::zero(),
    @provider.Stop,
  )
  let model = @testing.MockChatModel::new(
    [],
    expected,
    provider_name="mock-provider",
    model_id="mock-model",
  )
  let chat_model = model as &@provider.ChatModel
  let v4 = as_language_model_v4(chat_model)

  assert_eq(v4.specification_version(), "v4")
  assert_eq(v4.provider(), "mock-provider")
  assert_eq(v4.model_id(), "mock-model")

  let result = v4.do_generate(
    @provider.LanguageModelV4CallOptions::from_language_model_prompt([
      @provider.LanguageModelMessage::user("hello"),
    ]),
  )
  assert_eq(result.content.length(), 1)
  assert_eq(result.finish_reason.unified, @provider.V4FinishStop)
  assert_eq(result.to_chat_response().text, "hello")
}

///|
async test "ChatModel V4 adapter folds legacy warnings into stream start" {
  let warning = @provider.Warning::unsupported("topK")
  let expected = @provider.ChatResponse::new(
    "hello",
    "",
    [],
    @provider.Usage::new(input_tokens=1, output_tokens=1, total_tokens=2),
    @provider.Stop,
  ).with_diagnostics(None, None, Map([]), [warning])
  let model = @testing.MockChatModel::new(
    [
      @provider.StreamStart,
      @provider.Warning(warning),
      @provider.TextStart("text-0"),
      @provider.TextDelta(id="text-0", delta="hello"),
      @provider.TextEnd("text-0"),
      @provider.Finish(usage=expected.usage, reason=@provider.Stop),
    ],
    expected,
  )
  let v4 = as_language_model_v4(model as &@provider.ChatModel)
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  ignore(
    v4.do_stream(
      @provider.LanguageModelV4CallOptions::from_language_model_prompt([
        @provider.LanguageModelMessage::user("hello"),
      ]),
      event => events.push(event),
    ),
  )

  assert_eq(events.length(), 5)
  assert_true(
    events[0] is @provider.V4StreamStart(warnings~) && warnings == [warning],
  )
  assert_true(events[1] is @provider.V4TextStart(id="text-0", ..))
  assert_true(events[4] is @provider.V4Finish(..))
}
