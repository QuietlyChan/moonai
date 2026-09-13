///|
/// Reasoning handling strategy for the extract-reasoning middleware.
pub(all) enum ExtractReasoningMode {
  /// Re-emit reasoning events as text events so reasoning text lands in the
  /// visible output (models that only expose reasoning_content).
  ExtractMergeIntoText
  /// Strip reasoning events entirely.
  ExtractStrip
} derive(Debug, Eq)

///|
/// Extract-reasoning middleware.
///
/// The middleware wraps the stream event channel: in merge mode every
/// reasoning start/delta/end is re-emitted as the matching text part; in
/// strip mode reasoning events are dropped. All other events pass through
/// unchanged.
pub fn extract_reasoning_middleware(
  mode~ : ExtractReasoningMode,
) -> @provider.LanguageModelV4Middleware {
  @provider.LanguageModelV4Middleware::new(wrap_stream=async fn(
    context : @provider.LanguageModelV4MiddlewareContext,
  ) -> @provider.LanguageModelV4StreamResult {
    let converted_emit = async fn(
      part : @provider.LanguageModelV4StreamPart,
    ) -> Unit {
      match (mode, part) {
        (
          ExtractMergeIntoText,
          @provider.V4ReasoningStart(id~, provider_metadata~),
        ) => (context.emit)(@provider.V4TextStart(id~, provider_metadata~))
        (
          ExtractMergeIntoText,
          @provider.V4ReasoningDelta(id~, delta~, provider_metadata~),
        ) =>
          (context.emit)(@provider.V4TextDelta(id~, delta~, provider_metadata~))
        (ExtractMergeIntoText, @provider.V4ReasoningEnd(id~, provider_metadata~)
        ) => (context.emit)(@provider.V4TextEnd(id~, provider_metadata~))
        (_, part) => (context.emit)(part)
      }
    }
    context.model.do_stream(context.params, converted_emit)
  })
}
