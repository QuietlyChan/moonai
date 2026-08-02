///|
async test "streamText is provider-neutral and testable with a mock" {
  let usage : @moonai.Usage = {
    input_tokens: 2,
    output_tokens: 1,
    total_tokens: 3,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
  }
  let result : @moonai.ChatResponse = {
    text: "hello",
    reasoning: "",
    tool_calls: [],
    usage,
    finish_reason: @moonai.Stop,
  }
  let model = MockChatModel::new(
    [
      @moonai.StreamStart,
      @moonai.TextStart("text-0"),
      @moonai.TextDelta(id="text-0", delta="hello"),
      @moonai.TextEnd("text-0"),
      @moonai.Finish(usage~, reason=@moonai.Stop),
    ],
    result,
  )
  let deltas : Array[String] = []
  let actual = @moonai.streamText(model, prompt="say hello", on_event=event => {
    match event {
      @moonai.TextDelta(delta~, ..) => deltas.push(delta)
      _ => ()
    }
  })
  assert_eq(actual, result)
  assert_eq(deltas, ["hello"])
  assert_eq(model.captured_messages(), [@moonai.Message::user("say hello")])
}
