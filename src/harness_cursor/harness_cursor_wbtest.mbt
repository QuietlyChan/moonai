///|
test "cursor auth path follows the platform layout" {
  assert_eq(
    resolve_cursor_auth_path(
      home_directory="/home/u",
      appdata=Some("C:/Users/u/AppData/Roaming"),
      xdg_config_home=None,
    ),
    "C:/Users/u/AppData/Roaming/Cursor/auth.json",
  )
  assert_eq(
    resolve_cursor_auth_path(
      home_directory="/home/u",
      appdata=None,
      xdg_config_home=Some("/xdg"),
    ),
    "/xdg/cursor/auth.json",
  )
  assert_eq(
    resolve_cursor_auth_path(
      home_directory="/Users/u",
      appdata=None,
      xdg_config_home=None,
    ),
    "/Users/u/.cursor/auth.json",
  )
}

///|
test "cursor access token parsing and jwt expiry" {
  assert_eq(
    parse_cursor_access_token(payload={ "accessToken": "tok" }),
    Some("tok"),
  )
  assert_eq(parse_cursor_access_token(payload={ "nope": 1 }), None)
  // header.payload with exp = 1700000000
  let token = "eyJhbGciOiJIUzI1NiJ9.eyJleHAiOjE3MDAwMDAwMDB9.sig"
  assert_eq(cursor_jwt_expires_at(access_token=token), Some(1700000000))
  assert_eq(cursor_jwt_expires_at(access_token="not-a-jwt"), None)
  assert_false(
    cursor_token_expiring_soon(expires_at=2000000000, now=1700000000),
  )
  assert_true(cursor_token_expiring_soon(expires_at=1700000100, now=1700000000))
}

///|
test "cursor subscription resolution honors the memory credential store" {
  assert_eq(
    read_cursor_subscription(
      auth_json=Some("{\"accessToken\":\"tok\"}"),
      credential_store=Some("memory"),
    ),
    None,
  )
  assert_eq(
    read_cursor_subscription(
      auth_json=Some("{\"accessToken\":\"tok\"}"),
      credential_store=None,
    ),
    Some("tok"),
  )
  assert_eq(
    read_cursor_subscription(auth_json=None, credential_store=None),
    None,
  )
}

///|
test "cursor builtin catalog covers the documented tools" {
  let tools = cursor_builtin_tools()
  assert_true(tools.length() >= 29)
  let bash = cursor_builtin_tool(name="bash")
  assert_eq(
    bash.unwrap_or({ name: "", native_name: "", title: "", kind: Other, }).native_name,
    "shellToolCall",
  )
  let semantic = cursor_builtin_tool(name="semanticSearch")
  assert_eq(
    semantic.unwrap_or({ name: "", native_name: "", title: "", kind: Other, }).title,
    "Codebase Search",
  )
  assert_true(cursor_builtin_tool(name="mcpToolCall") is None)
}
