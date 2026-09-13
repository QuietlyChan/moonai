///|
priv struct FlakyStreamLanguageModel {
  failures : Array[Error]
  call_count : Ref[Int]
  streams_a_delta_first : Bool
}

///|
impl @provider.LanguageModelV4 for FlakyStreamLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for FlakyStreamLanguageModel with fn provider(
  _self,
) -> String {
  "test.stream-retries"
}

///|
impl @provider.LanguageModelV4 for FlakyStreamLanguageModel with fn model_id(
  _self,
) -> String {
  "flaky-stream-model"
}

///|
impl @provider.LanguageModelV4 for FlakyStreamLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
impl @provider.LanguageModelV4 for FlakyStreamLanguageModel with fn do_generate(
  _self,
  _options,
) {
  fail("flaky stream model does not support generate")
}

///|
impl @provider.LanguageModelV4 for FlakyStreamLanguageModel with fn do_stream(
  self,
  _options,
  on_event,
) {
  let index = self.call_count.val
  self.call_count.val = index + 1
  if index < self.failures.length() {
    if self.streams_a_delta_first {
      on_event(@provider.V4StreamStart(warnings=[]))
      on_event(@provider.V4TextStart(id="text-1", provider_metadata=Map([])))
      on_event(
        @provider.V4TextDelta(
          id="text-1",
          delta="partial",
          provider_metadata=Map([]),
        ),
      )
    }
    raise self.failures[index]
  }
  on_event(@provider.V4StreamStart(warnings=[]))
  on_event(@provider.V4TextStart(id="text-1", provider_metadata=Map([])))
  on_event(
    @provider.V4TextDelta(
      id="text-1",
      delta="recovered",
      provider_metadata=Map([]),
    ),
  )
  on_event(@provider.V4TextEnd(id="text-1", provider_metadata=Map([])))
  on_event(
    @provider.V4Finish(
      usage=@provider.LanguageModelV4Usage::from_usage(
        @provider.Usage::new(input_tokens=1, output_tokens=1),
      ),
      reason={ unified: @provider.V4FinishStop, raw: None, },
      provider_metadata=Map([]),
    ),
  )
  @provider.LanguageModelV4StreamResult::new(None, None)
}

///|
fn flaky_stream_model(
  failures : Array[Error],
  streams_a_delta_first? : Bool = false,
) -> FlakyStreamLanguageModel {
  { failures, call_count: Ref(0), streams_a_delta_first, }
}

///|
fn retryable_api_error(message~ : String) -> Error {
  @provider.APICallError(
    message~,
    url="https://example.test/v1/chat",
    request_body="",
    request_headers=Map([]),
    status_code=Some(503),
    response_headers=Map([]),
    response_body="",
    is_retryable=true,
    data=None,
    cause=None,
  )
}

///|
fn no_delay_retry_policy(max_retries : Int) -> @provider.RetryPolicy raise {
  @provider.RetryPolicy::new(
    max_retries~,
    initial_delay_ms=0,
    max_delay_ms=0,
    backoff_factor=1.0,
  )
}

///|
fn retry_call_options() -> @provider.LanguageModelV4CallOptions {
  @provider.LanguageModelV4CallOptions::from_language_model_prompt([
    @provider.LanguageModelMessage::user("say hi"),
  ])
}

///|
async test "stream retries middleware retries a pre-stream failure" {
  let model = flaky_stream_model([retryable_api_error(message="upstream reset")])
  let wrapped = wrap_language_model_v4(
    model as &@provider.LanguageModelV4,
    stream_retries_middleware(retry_policy=no_delay_retry_policy(2)),
  )
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  let result = wrapped.do_stream(retry_call_options(), event => {
    events.push(event)
  })
  assert_eq(model.call_count.val, 2)
  assert_eq(events.length(), 5)
  assert_true(events[2] is @provider.V4TextDelta(delta="recovered", ..))
  assert_true(result.request is None)
}

///|
async test "stream retries middleware never retries after events were delivered" {
  let model = flaky_stream_model(
    [retryable_api_error(message="mid-stream reset")],
    streams_a_delta_first=true,
  )
  let wrapped = wrap_language_model_v4(
    model as &@provider.LanguageModelV4,
    stream_retries_middleware(retry_policy=no_delay_retry_policy(3)),
  )
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  try
    wrapped.do_stream(retry_call_options(), event => events.push(event))
  catch {
    @provider.APICallError(message="mid-stream reset", ..) => ()
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected the mid-stream error to propagate")
  }
  assert_eq(model.call_count.val, 1)
  // Only the events of the failed attempt were delivered; no duplicated
  // re-emission from a retried attempt.
  assert_eq(events.length(), 3)
}

///|
async test "stream retries middleware raises after exhausting retries" {
  let model = flaky_stream_model([
    retryable_api_error(message="upstream reset"),
    retryable_api_error(message="upstream reset"),
    retryable_api_error(message="upstream reset"),
  ])
  let wrapped = wrap_language_model_v4(
    model as &@provider.LanguageModelV4,
    stream_retries_middleware(retry_policy=no_delay_retry_policy(2)),
  )
  try wrapped.do_stream(retry_call_options(), _ => ()) catch {
    @provider.APICallError(message="upstream reset", ..) => ()
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected the last retryable error to surface")
  }
  // Initial attempt plus two retries, then the failure surfaces.
  assert_eq(model.call_count.val, 3)
}

///|
async test "stream retries middleware passes non-retryable errors through" {
  let model = flaky_stream_model([
    @provider.APICallError(
      message="invalid request",
      url="https://example.test/v1/chat",
      request_body="",
      request_headers=Map([]),
      status_code=Some(400),
      response_headers=Map([]),
      response_body="",
      is_retryable=false,
      data=None,
      cause=None,
    ),
  ])
  let wrapped = wrap_language_model_v4(
    model as &@provider.LanguageModelV4,
    stream_retries_middleware(retry_policy=no_delay_retry_policy(3)),
  )
  try wrapped.do_stream(retry_call_options(), _ => ()) catch {
    @provider.APICallError(message="invalid request", ..) => ()
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected the invalid request to propagate")
  }
  assert_eq(model.call_count.val, 1)
}

///|
async test "stream retries middleware respects max_retries zero" {
  let model = flaky_stream_model([retryable_api_error(message="upstream reset")])
  let wrapped = wrap_language_model_v4(
    model as &@provider.LanguageModelV4,
    stream_retries_middleware(retry_policy=no_delay_retry_policy(0)),
  )
  try wrapped.do_stream(retry_call_options(), _ => ()) catch {
    @provider.APICallError(message="upstream reset", ..) => ()
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected the retryable error to propagate with zero retries")
  }
  assert_eq(model.call_count.val, 1)
}
