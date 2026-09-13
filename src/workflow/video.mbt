///|
/// Workflow-safe reference to the environment variable that contains the
/// secret used to sign and verify tool approvals (upstream
/// `WorkflowToolApprovalSecret`).
pub(all) struct WorkflowToolApprovalSecret {
  environment_variable : String
} derive(Debug, Eq)

///|
/// Resolve the workflow tool approval secret from its environment variable.
/// The value feeds the core `ToolApprovalSecret` used by generateText's
/// `experimental_tool_approval_secret`.
pub fn resolve_workflow_tool_approval_secret(
  secret~ : WorkflowToolApprovalSecret,
) -> String raise WorkflowError {
  match @env.get_env_var(secret.environment_variable) {
    Some(value) if value != "" => value
    _ =>
      raise WorkflowError(
        message="workflow tool approval secret environment variable \{secret.environment_variable} is not set",
      )
  }
}

///|
/// Durable video generation for a workflow: submit via `do_start` with an
/// idempotency key (derived from the step id unless one is present), then
/// poll `do_status` until the job completes or fails. Hosted videos remain
/// URLs and are not downloaded automatically.
pub async fn workflow_generate_video(
  model~ : &@provider.VideoModelV4,
  options~ : @provider.VideoModelV4CallOptions,
  step_id~ : String,
  poll_interval_ms? : Int = 5000,
  poll_timeout_ms? : Int = 600_000,
) -> @provider.VideoModelV4Result {
  let headers = @provider_utils.copy_headers(options.headers)
  let mut has_idempotency_key = false
  for key, _ in headers.iter2() {
    if key.to_lower() == "idempotency-key" {
      has_idempotency_key = true
    }
  }
  if !has_idempotency_key {
    headers["idempotency-key"] = "aisdk_workflow_video_\{step_id}"
  }
  let submit_options = { ..options, headers, }
  let start = (model as &@provider.VideoModelV4).do_start(submit_options)
  let cancellation_token = options.cancellation_token
  let poll_started_at = @env.now()
  for ;; {
    @provider.check_cancellation(cancellation_token)
    @provider_utils.sleep_with_cancellation(
      poll_interval_ms, cancellation_token,
    )
    if @env.now() - poll_started_at > poll_timeout_ms.to_uint64() {
      fail("workflow video polling exceeded \{poll_timeout_ms}ms")
    }
    let status = (model as &@provider.VideoModelV4).do_status(
      @provider.VideoModelV4OperationStatusCallOptions::new(
        operation_id=start.operation_id,
        headers=@provider_utils.copy_headers(headers),
        retry_policy=options.retry_policy,
        cancellation_token?,
      ),
    )
    match status.state {
      @provider.OperationSucceeded =>
        return status.result.unwrap_or(@provider.VideoModelV4Result::new([]))
      @provider.OperationFailed => fail("workflow video generation failed")
      _ => ()
    }
  }
}
