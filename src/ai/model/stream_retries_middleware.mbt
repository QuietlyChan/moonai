///|
/// Stream-retries middleware (AI SDK #18718 basic semantics).
///
/// Wraps the stream so a retryable failure — flagged API errors and
/// transport-level failures — restarts the underlying stream after an
/// exponential backoff, up to `max_retries`. Retries apply only while the
/// current attempt has not delivered any event yet: once an event crossed
/// the emit channel it cannot be withdrawn, so a later failure propagates
/// instead of duplicating output. The wrapped model's own transport-level
/// retry policy stays in charge of connection retries; this middleware
/// adds the model-boundary layer on top.
pub fn stream_retries_middleware(
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
) -> @provider.LanguageModelV4Middleware {
  @provider.LanguageModelV4Middleware::new(wrap_stream=async fn(
    context : @provider.LanguageModelV4MiddlewareContext,
  ) -> @provider.LanguageModelV4StreamResult {
    let delivered = Ref(false)
    let mut attempt = 0
    let mut delay = @provider_utils.initial_retry_delay(retry_policy)
    let mut settled : @provider.LanguageModelV4StreamResult? = None
    while settled is None {
      @provider.check_cancellation(context.params.cancellation_token)
      delivered.val = false
      let counting_emit = async fn(
        part : @provider.LanguageModelV4StreamPart,
      ) -> Unit {
        delivered.val = true
        (context.emit)(part)
      }
      settled = try {
        let result = context.model.do_stream(context.params, counting_emit)
        Some(result)
      } catch {
        error if !delivered.val &&
          @provider_utils.is_retryable_error(error) &&
          attempt < retry_policy.max_retries => {
          @provider_utils.sleep_with_cancellation(
            delay,
            context.params.cancellation_token,
          )
          delay = @provider_utils.next_retry_delay(retry_policy, delay)
          attempt = attempt + 1
          None
        }
        error => raise error
      }
    }
    settled.unwrap()
  })
}
