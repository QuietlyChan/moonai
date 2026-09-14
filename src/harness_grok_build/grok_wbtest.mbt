///|
test "grok oauth record selection matches issuer::client scopes" {
  let scope_key = "https://cli-chat-proxy.grok.com/v1::" + XAI_CLIENT_ID
  let auth_json = Json::object(
    Map([
      (
        scope_key,
        Json::object(
          Map([
            ("key", Json::string("tok")),
            ("refresh_token", Json::string("ref")),
            ("expires_at", Json::number(1700000000000)),
          ]),
        ),
      ),
    ]),
  )
  let record = grok_select_oauth_record(value=auth_json)
  guard record is Some(selected) else { fail("expected selected record") }
  assert_eq(selected.key, "tok")
  assert_eq(selected.refresh_token, "ref")
  assert_eq(selected.expires_at, 1700000000000L)
  assert_eq(selected.issuer, "https://cli-chat-proxy.grok.com/v1")
}

///|
test "grok oauth record rejects wrong client id and malformed records" {
  let bad_scope = "https://other::not-the-client"
  let bad_record : Json = Json::object(
    Map([
      (
        bad_scope,
        Json::object(
          Map([
            ("key", Json::string("tok")),
            ("refresh_token", Json::string("ref")),
            ("expires_at", Json::number(1)),
          ]),
        ),
      ),
    ]),
  )
  assert_true(grok_select_oauth_record(value=bad_record) is None)
  let bad_key = "https://cli-chat-proxy.grok.com/v1::" + XAI_CLIENT_ID
  let bad_key_record : Json = Json::object(
    Map([(bad_key, Json::object(Map([("key", Json::number(1))])))]),
  )
  assert_true(grok_select_oauth_record(value=bad_key_record) is None)
  assert_true(grok_select_oauth_record(value={ "nope": true }) is None)
}

///|
test "grok expires_at normalization handles seconds and millis" {
  assert_eq(
    grok_normalize_expires_at(Json::number(1700000000)),
    Some(1700000000000L),
  )
  assert_eq(
    grok_normalize_expires_at(Json::number(1700000000000)),
    Some(1700000000000L),
  )
}

///|
test "grok native subscription decision mirrors upstream" {
  assert_false(
    should_resolve_grok_native_subscription(
      ai_gateway_auth=true,
      has_direct_credential=false,
    ),
  )
  assert_false(
    should_resolve_grok_native_subscription(
      ai_gateway_auth=false,
      has_direct_credential=true,
    ),
  )
  assert_true(
    should_resolve_grok_native_subscription(
      ai_gateway_auth=false,
      has_direct_credential=false,
    ),
  )
}
