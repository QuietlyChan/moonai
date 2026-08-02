///|
/// Deterministic model used by SDK consumers and agent tests.
pub struct MockChatModel {
  priv provider_name : String
  priv model_id : String
  priv events : Array[@moonai.StreamEvent]
  priv result : @moonai.ChatResponse
  priv captured_messages : Array[@moonai.Message]
}

///|
/// Construct a deterministic mock model.
pub fn MockChatModel::new(
  events : Array[@moonai.StreamEvent],
  result : @moonai.ChatResponse,
  provider_name? : String = "mock",
  model_id? : String = "mock-model",
) -> MockChatModel {
  { provider_name, model_id, events, result, captured_messages: [] }
}

///|
/// Return the messages received during the latest call.
pub fn MockChatModel::captured_messages(
  self : MockChatModel,
) -> Array[@moonai.Message] {
  self.captured_messages.copy()
}

///|
pub impl @moonai.ChatModel for MockChatModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @moonai.ChatModel for MockChatModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @moonai.ChatModel for MockChatModel with fn stream(
  self,
  options,
  on_event,
) {
  self.captured_messages.clear()
  for message in options.messages {
    self.captured_messages.push(message)
  }
  for event in self.events {
    on_event(event)
  }
  self.result
}
