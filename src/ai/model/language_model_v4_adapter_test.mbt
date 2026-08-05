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
