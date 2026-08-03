///|
/// Return whether an HTTP status conventionally represents a transient
/// failure for an idempotent provider request.
pub fn is_retryable_status(status_code : Int) -> Bool {
  status_code == 408 ||
  status_code == 409 ||
  status_code == 425 ||
  status_code == 429 ||
  status_code >= 500
}

///|
/// Return the first retry delay, capped by the configured maximum.
pub fn initial_retry_delay(policy : @moonai.RetryPolicy) -> Int {
  if policy.initial_delay_ms > policy.max_delay_ms {
    policy.max_delay_ms
  } else {
    policy.initial_delay_ms
  }
}

///|
/// Compute the next exponential retry delay, capped by the policy.
pub fn next_retry_delay(policy : @moonai.RetryPolicy, current : Int) -> Int {
  if current <= 0 || policy.max_delay_ms <= 0 {
    0
  } else {
    let candidate = (current.to_double() * policy.backoff_factor).to_int()
    if candidate > policy.max_delay_ms {
      policy.max_delay_ms
    } else {
      candidate
    }
  }
}

///|
/// Sleep in short slices so a cooperative cancellation token is observed
/// during a retry backoff instead of only after the full delay.
pub async fn sleep_with_cancellation(
  delay_ms : Int,
  cancellation_token : @moonai.CancellationToken?,
) -> Unit {
  let mut remaining = delay_ms
  while remaining > 0 {
    @moonai.check_cancellation(cancellation_token)
    let step = if remaining > 25 { 25 } else { remaining }
    @async.sleep(step)
    remaining = remaining - step
  }
  @moonai.check_cancellation(cancellation_token)
}
