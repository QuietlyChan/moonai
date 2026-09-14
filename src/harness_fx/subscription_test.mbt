///|
test "fx environment variable mapping covers both providers" {
  assert_eq(
    fx_access_token_environment_variable(provider="chatgpt"),
    Some(FX_CHATGPT_ACCESS_TOKEN_ENV),
  )
  assert_eq(
    fx_account_id_environment_variable(provider="grok"),
    Some(FX_GROK_ACCOUNT_ID_ENV),
  )
  assert_true(fx_access_token_environment_variable(provider="other") is None)
}

///|
test "fx merge folds credentials into the environment" {
  let environment : Map[String, String] = Map([])
  let merged = fx_merge_subscription_environment(
    environment~,
    provider="grok",
    credential={ access_token: "tok", account_id: "acc", },
  )
  assert_eq(merged.get(FX_GROK_ACCESS_TOKEN_ENV), Some("tok"))
  assert_eq(merged.get(FX_GROK_ACCOUNT_ID_ENV), Some("acc"))
}

///|
test "fx auth file forwarding skips when brokering is available" {
  let env : Map[String, String] = Map([(FX_CHATGPT_ACCESS_TOKEN_ENV, "tok")])
  let sandbox : Map[String, String] = Map([])
  let forwarded = fx_subscription_authentication_files(
    env~,
    sandbox_env=sandbox,
    credential_brokering_available=true,
  )
  assert_eq(forwarded.length(), 0)
  let forwarded_plain = fx_subscription_authentication_files(
    env~,
    sandbox_env=sandbox,
    credential_brokering_available=false,
  )
  assert_eq(forwarded_plain, [FX_CHATGPT_ACCESS_TOKEN_ENV])
}
