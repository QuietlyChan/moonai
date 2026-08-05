///|
/// Deterministic model used by SDK consumers and agent tests.
pub struct MockChatModel {
  priv provider_name : String
  priv model_id : String
  priv events : Array[@provider.StreamEvent]
  priv result : @provider.ChatResponse
  priv supported_url_rules : Array[@provider.SupportedUrlRule]
  priv captured_messages : Array[@provider.LanguageModelMessage]
  priv mut captured_tool_choice : @provider.ToolChoice?
}

///|
/// Construct a deterministic mock model.
pub fn MockChatModel::new(
  events : Array[@provider.StreamEvent],
  result : @provider.ChatResponse,
  provider_name? : String = "mock",
  model_id? : String = "mock-model",
  supported_urls? : Array[@provider.SupportedUrlRule] = [],
) -> MockChatModel {
  {
    provider_name,
    model_id,
    events,
    result,
    supported_url_rules: supported_urls.copy(),
    captured_messages: [],
    captured_tool_choice: None,
  }
}

///|
/// Return the messages received during the latest call.
pub fn MockChatModel::captured_messages(
  self : MockChatModel,
) -> Array[@provider.LanguageModelMessage] {
  self.captured_messages.copy()
}

///|
/// Return the tool choice received during the latest call.
pub fn MockChatModel::captured_tool_choice(
  self : MockChatModel,
) -> @provider.ToolChoice? {
  self.captured_tool_choice
}

///|
pub impl @provider.ChatModel for MockChatModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ChatModel for MockChatModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ChatModel for MockChatModel with fn supported_urls(self) -> Array[
  @provider.SupportedUrlRule,
] {
  self.supported_url_rules.copy()
}

///|
pub impl @provider.ChatModel for MockChatModel with fn generate(self, options) {
  self.captured_tool_choice = options.tool_choice
  self.captured_messages.clear()
  for message in options.messages {
    self.captured_messages.push(message)
  }
  self.result
}

///|
pub impl @provider.ChatModel for MockChatModel with fn stream(
  self,
  options,
  on_event,
) {
  self.captured_tool_choice = options.tool_choice
  self.captured_messages.clear()
  for message in options.messages {
    self.captured_messages.push(message)
  }
  for event in self.events {
    on_event(event)
  }
  self.result
}
