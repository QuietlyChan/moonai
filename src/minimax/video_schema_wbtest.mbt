///|
test "MiniMax video schemas validate create and poll response fields" {
  assert_eq(
    minimax_create_video_response_validation_error({ "task_id": null }),
    None,
  )
  assert_true(
    minimax_create_video_response_validation_error({ "task_id": 42 })
    is Some(message) &&
    message.contains("task_id"),
  )
  let valid : Json = {
    "task": {
      "id": "task-1",
      "status": "succeeded",
      "content": { "url": "https://example.com/video.mp4" },
      "resolution": "2K",
      "duration": 5,
      "ratio": "16:9",
      "usage": {
        "total_seconds": 5,
        "input_seconds": null,
        "output_seconds": 5,
      },
      "error": null,
    },
  }
  assert_eq(minimax_video_status_response_validation_error(valid), None)
  assert_true(
    minimax_video_status_response_validation_error({ "task": { "status": 1 } })
    is Some(message) &&
    message.contains("status"),
  )
  assert_true(
    minimax_video_status_response_validation_error({
      "task": { "usage": { "total_seconds": "five" } },
    })
    is Some(message) &&
    message.contains("total_seconds"),
  )
}

///|
test "MiniMax video schemas raise structured invalid response errors" {
  let invalid : Json = { "task": { "error": { "code": true } } }
  try validate_minimax_video_status_response(invalid) catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("error.code"))
      assert_eq(data, invalid)
    }
    error => fail("unexpected MiniMax schema error: \{error}")
  } noraise {
    _ => fail("expected an invalid MiniMax status response")
  }
}
