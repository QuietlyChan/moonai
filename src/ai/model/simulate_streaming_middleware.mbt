///|
/// Simulate-streaming middleware: converts a non-streaming generate result
/// into a stream of deltas (AI SDK `simulateStreamingMiddleware`).
///
/// `wrap_stream` first drains the real generate result, then emits the
/// normalized content as start/delta/end (and tool-call) stream parts
/// through the context's `emit` channel, finishing with a synthetic finish
/// part. Callers consume it exactly like a genuine stream.
pub fn simulate_streaming_middleware() -> @provider.LanguageModelV4Middleware {
  @provider.LanguageModelV4Middleware::new(wrap_stream=async fn(
    context : @provider.LanguageModelV4MiddlewareContext,
  ) -> @provider.LanguageModelV4StreamResult {
    let result = context.generate()
    let mut text_index = 0
    let mut reasoning_index = 0
    for item in result.content {
      match item {
        @provider.LanguageModelV4Content::V4TextOutput(output) => {
          let id = "txt-\{text_index}"
          text_index = text_index + 1
          (context.emit)(
            @provider.V4TextStart(
              id~,
              provider_metadata=output.provider_metadata,
            ),
          )
          (context.emit)(
            @provider.V4TextDelta(
              id~,
              delta=output.text,
              provider_metadata=output.provider_metadata,
            ),
          )
          (context.emit)(
            @provider.V4TextEnd(id~, provider_metadata=output.provider_metadata),
          )
        }
        @provider.LanguageModelV4Content::V4ReasoningOutput(output) => {
          let id = "reasoning-\{reasoning_index}"
          reasoning_index = reasoning_index + 1
          (context.emit)(
            @provider.V4ReasoningStart(
              id~,
              provider_metadata=output.provider_metadata,
            ),
          )
          (context.emit)(
            @provider.V4ReasoningDelta(
              id~,
              delta=output.text,
              provider_metadata=output.provider_metadata,
            ),
          )
          (context.emit)(
            @provider.V4ReasoningEnd(
              id~,
              provider_metadata=output.provider_metadata,
            ),
          )
        }
        @provider.LanguageModelV4Content::V4ToolCallOutput(call) =>
          (context.emit)(@provider.V4ToolCallReady(call))
        _ => ()
      }
    }
    (context.emit)(
      @provider.V4Finish(
        usage=result.usage,
        reason=result.finish_reason,
        provider_metadata=result.provider_metadata,
      ),
    )
    @provider.LanguageModelV4StreamResult::new(result.request, result.response)
  })
}
