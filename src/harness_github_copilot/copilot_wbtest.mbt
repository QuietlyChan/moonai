///|
test "copilot account selection prefers the last logged in user" {
  let account = select_github_copilot_account(config={
    "last_logged_in_user": { "host": "github.com", "login": "octocat" },
    "logged_in_users": [{ "host": "ghe.example.com", "login": "other" }],
  })
  let selected = account.unwrap_or({ host: "", login: "", })
  assert_eq(selected.login, "octocat")
  assert_eq(selected.host, "https://github.com/")
}

///|
test "copilot account selection rejects malformed entries" {
  assert_true(
    select_github_copilot_account(config={
      "last_logged_in_user": { "host": "github.com" },
    })
    is None,
  )
  assert_true(
    select_github_copilot_account(config={ "logged_in_users": "nope" }) is None,
  )
}

///|
test "copilot plaintext token lookup is keyed and non-empty" {
  let config : Json = {
    "copilotTokens": {
      "github.com:octocat": "ghu_tok",
      "ghe.example.com:empty": "",
    },
  }
  assert_eq(
    get_plaintext_copilot_token(config~, account_key="github.com:octocat"),
    Some("ghu_tok"),
  )
  assert_eq(
    get_plaintext_copilot_token(config~, account_key="ghe.example.com:empty"),
    None,
  )
  assert_eq(get_plaintext_copilot_token(config~, account_key="missing"), None)
}

///|
test "github host normalization prefixes scheme and trims slashes" {
  assert_eq(normalize_github_host("github.com"), Some("https://github.com/"))
  assert_eq(
    normalize_github_host("https://ghe.example.com"),
    Some("https://ghe.example.com/"),
  )
  assert_eq(normalize_github_host("  "), None)
}
