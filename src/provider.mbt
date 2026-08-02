///|
/// Common interface implemented by every language model provider package.
pub(open) trait ChatModel {
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn stream(Self, ChatCallOptions, async (StreamEvent) -> Unit) -> ChatResponse
}
