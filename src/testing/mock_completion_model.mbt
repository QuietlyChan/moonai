///|
/// Deterministic legacy completion model for SDK consumer tests.
pub struct MockCompletionModel {
  priv provider_name : String
  priv model_id : String
  priv events : Array[@provider.StreamEvent]
  priv result : @provider.CompletionResponse
  priv mut captured_prompt : String
}

///|
/// Construct a deterministic completion model.
pub fn MockCompletionModel::new(
  events : Array[@provider.StreamEvent],
  result : @provider.CompletionResponse,
  provider_name? : String = "mock",
  model_id? : String = "mock-completion-model",
) -> MockCompletionModel {
  { provider_name, model_id, events, result, captured_prompt: "" }
}

///|
/// Return the prompt received during the latest call.
pub fn MockCompletionModel::captured_prompt(
  self : MockCompletionModel,
) -> String {
  self.captured_prompt
}

///|
pub impl @provider.CompletionModel for MockCompletionModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.CompletionModel for MockCompletionModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.CompletionModel for MockCompletionModel with fn generate(
  self,
  options,
) {
  self.captured_prompt = options.prompt
  self.result
}

///|
pub impl @provider.CompletionModel for MockCompletionModel with fn stream(
  self,
  options,
  on_event,
) {
  self.captured_prompt = options.prompt
  for event in self.events {
    on_event(event)
  }
  self.result
}
