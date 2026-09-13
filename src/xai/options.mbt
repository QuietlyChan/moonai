///|
/// xAI chat model ids (https://docs.x.ai/docs/models), e.g. `grok-4.3`,
/// `grok-4.6`, `grok-4.20(-dated)-(non-)?reasoning`.
pub type XaiChatModelId = String

///|
/// xAI image model ids, e.g. `grok-2-image-v1`.
pub type XaiImageModelId = String

///|
/// The grok-4.20 reasoning and non-reasoning models (including dated
/// variants such as `grok-4.20-0309-reasoning`) reject the reasoning effort
/// parameter for every value including `none`; other models accept it.
pub fn supports_reasoning_effort(model_id : String) -> Bool {
  let prefix = "grok-4.20"
  guard model_id.has_prefix(prefix) else { return true }
  let rest = model_id[prefix.length():].to_owned()
  // Strip the optional dated segment "-NNNN" (e.g. grok-4.20-0309-reasoning).
  fn is_ascii_digit(c : UInt16) -> Bool {
    c >= 48 && c <= 57
  }

  let rest = if rest.length() > 5 &&
    rest.has_prefix("-") &&
    is_ascii_digit(rest[1]) &&
    is_ascii_digit(rest[2]) &&
    is_ascii_digit(rest[3]) &&
    is_ascii_digit(rest[4]) {
    rest[5:].to_owned()
  } else {
    rest
  }
  !(rest == "-reasoning" || rest == "-non-reasoning")
}

///|
/// Camel-case spelling of `supports_reasoning_effort`.
pub fn supportsReasoningEffort(model_id : String) -> Bool {
  supports_reasoning_effort(model_id)
}

///|
/// Provider options accepted under the `xai` namespace (all optional):
///
/// - chat: `logprobs` (bool), `topLogprobs` (int), `serviceTier`
///   (`"auto" | "on" | "flex"`), `reasoningEffort`
///   (`"none" | "low" | "medium" | "high" | "xhigh"`),
///   `parallel_function_calling` (bool).
/// - image: `output_format`, `sync_mode`, `aspect_ratio`, `resolution`,
///   `quality`, `user`.
