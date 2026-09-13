///|
test "baseten error message resolves both envelopes" {
  assert_eq(
    baseten_error_to_message({ "error": "please check the model you provided" }),
    Some("please check the model you provided"),
  )
  assert_eq(
    baseten_error_to_message({ "error": { "message": "boom" } }),
    Some("boom"),
  )
  assert_eq(baseten_error_to_message({ "error": 42 }), None)
}

///|
test "baseten chat base url validates the dedicated deployment shape" {
  let plain = create_baseten(api_key="sk-test")
  assert_eq(plain.chat_base_url(), "https://inference.baseten.co/v1")
  let sync = create_baseten(
    api_key="sk-test",
    model_url="https://model-xxxx.api.baseten.co/environments/production/sync/v1",
  )
  assert_eq(
    sync.chat_base_url(),
    "https://model-xxxx.api.baseten.co/environments/production/sync/v1",
  )
  let predict = create_baseten(
    api_key="sk-test",
    model_url="https://model-xxxx.api.baseten.co/model/predict",
  )
  try predict.chat_base_url() catch {
    _ => assert_true(true)
  } noraise {
    _ => fail("expected /predict rejection")
  }
}
