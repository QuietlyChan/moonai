///|
test "prodia image job config maps size and provider options" {
  let warnings : Array[@provider.Warning] = []
  let options = @provider.ImageModelV4CallOptions::new(
    prompt="a red fox",
    size="512x768",
    seed=42,
  )
  let config = prodia_image_job_config(
    options,
    Map([("steps", Json::number(30))]),
    warnings,
  )
  assert_true(
    config
    is {
      "prompt": "a red fox",
      "width": 512,
      "height": 768,
      "seed": 42,
      "steps": 30,
      ..
    },
  )
  assert_eq(warnings.length(), 0)
}

///|
test "prodia image job config warns on malformed size" {
  let warnings : Array[@provider.Warning] = []
  let options = @provider.ImageModelV4CallOptions::new(
    prompt="a red fox",
    size="wide",
  )
  let config = prodia_image_job_config(options, Map([]), warnings)
  assert_false(config.contains("width"))
  assert_eq(warnings.length(), 1)
  assert_true(warnings[0] is @provider.Warning::Unsupported(feature="size", ..))
}

///|
test "prodia job metadata flattens state metrics and price" {
  let metadata = prodia_job_metadata({
    "id": "job-9",
    "state": { "current": "succeeded" },
    "metrics": { "elapsed": 2.5 },
    "price": { "product": "image", "dollars": 0.01 },
  })
  guard metadata.get("prodia") is Some(Object(fields)) else {
    fail("expected prodia metadata")
  }
  assert_eq(fields.get("id"), Some(Json::string("job-9")))
  assert_eq(fields.get("state"), Some(Json::string("succeeded")))
  assert_true(fields.get("metrics") is Some({ "elapsed": 2.5, .. }))
  assert_true(fields.get("price") is Some({ "dollars": 0.01, .. }))
}

///|
test "prodia error message resolves flat payloads" {
  assert_eq(
    prodia_error_to_message({ "message": "quota exceeded" }),
    Some("quota exceeded"),
  )
}
