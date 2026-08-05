///|
async test "V4 high-level text generation uses the shared prompt layer" {
  let expected = @provider.ChatResponse::new(
    "hello",
    "",
    [],
    @provider.Usage::zero(),
    @provider.Stop,
  )
  let mock = @testing.MockChatModel::new(
    [
      @provider.TextStart("text-0"),
      @provider.TextDelta(id="text-0", delta="hello"),
      @provider.TextEnd("text-0"),
    ],
    expected,
    provider_name="mock-v4",
    model_id="mock-chat",
  )
  let model = @model.as_language_model_v4(mock as &@provider.ChatModel)
  let result = generate_text(model, prompt="hello")
  assert_eq(result.finish_reason.unified, @provider.V4FinishStop)
  assert_eq(result.to_chat_response().text, "hello")
}

///|
async test "V4 high-level streaming preserves provider stream events" {
  let expected = @provider.ChatResponse::new(
    "hello",
    "",
    [],
    @provider.Usage::zero(),
    @provider.Stop,
  )
  let mock = @testing.MockChatModel::new(
    [@provider.TextDelta(id="text-0", delta="hello")],
    expected,
    provider_name="mock-v4",
    model_id="mock-chat",
  )
  let model = @model.as_language_model_v4(mock as &@provider.ChatModel)
  let mut events = 0
  let _ = stream_text(model, prompt="hello", on_event=event => {
    match event {
      @provider.V4TextDelta(..) => events = events + 1
      _ => ()
    }
  })
  assert_eq(events, 1)
}
