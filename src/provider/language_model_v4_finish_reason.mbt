///|
/// Unified finish reason used by the V4 language-model contract.
pub(all) enum LanguageModelV4UnifiedFinishReason {
  V4FinishStop
  V4FinishLength
  V4FinishContentFilter
  V4FinishToolCalls
  V4FinishError
  V4FinishOther
} derive(Debug, Eq)

///|
/// Finish reason with an optional provider-native value.
pub(all) struct LanguageModelV4FinishReason {
  unified : LanguageModelV4UnifiedFinishReason
  raw : String?
} derive(Debug, Eq)

///|
/// Convert a normalized ChatModel finish reason into V4.
pub fn LanguageModelV4FinishReason::from_finish_reason(
  reason : FinishReason,
) -> LanguageModelV4FinishReason {
  match reason {
    Stop => { unified: V4FinishStop, raw: None }
    Length => { unified: V4FinishLength, raw: None }
    ToolCalls => { unified: V4FinishToolCalls, raw: None }
    ContentFilter => { unified: V4FinishContentFilter, raw: None }
    Error => { unified: V4FinishError, raw: None }
    Unknown(value) => { unified: V4FinishOther, raw: Some(value) }
  }
}

///|
/// Convert a V4 finish reason back to the normalized ChatModel spelling.
pub fn LanguageModelV4FinishReason::to_finish_reason(
  self : LanguageModelV4FinishReason,
) -> FinishReason {
  match self.unified {
    V4FinishStop => Stop
    V4FinishLength => Length
    V4FinishContentFilter => ContentFilter
    V4FinishToolCalls => ToolCalls
    V4FinishError => Error
    V4FinishOther => Unknown(self.raw.unwrap_or("other"))
  }
}

///|
/// Construct an unspecified V4 finish reason for an incomplete stream.
pub fn LanguageModelV4FinishReason::unknown() -> LanguageModelV4FinishReason {
  { unified: V4FinishOther, raw: None }
}

///|
/// Replace the provider-native finish reason while preserving normalization.
pub fn LanguageModelV4FinishReason::with_raw(
  self : LanguageModelV4FinishReason,
  raw : String?,
) -> LanguageModelV4FinishReason {
  { unified: self.unified, raw }
}
