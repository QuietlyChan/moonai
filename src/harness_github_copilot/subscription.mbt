///|
/// Version of the Moonai harness-github-copilot subpackage.
pub const VERSION : String = "0.1.0"

///|
/// A GitHub account entry selected from the Copilot CLI config.
pub(all) struct GitHubCopilotAccount {
  host : String
  login : String
} derive(Debug, Eq)

///|
/// Normalize a GitHub host to `https://<host>/` origin form. Purely
/// syntactic: trims whitespace/slashes and prefixes the scheme. Host
/// allow/deny lists (github.com vs GHE instances) remain the caller's
/// policy.
pub fn normalize_github_host(host : String) -> String? {
  let trimmed = host.trim().to_owned()
  guard trimmed != "" else { return None }
  fn strip_trailing_slash(text : String) -> String {
    let t = text
    while t.has_suffix("/") {
      // drop one trailing slash per iteration
      let shorter = t[:t.length() - 1].to_owned()
      ignore(shorter)
      return strip_trailing_slash(shorter)
    }
    t
  }

  if trimmed.has_prefix("https://") || trimmed.has_prefix("http://") {
    let rest = trimmed.split("//").to_array().get(1).unwrap_or("").to_owned()
    let cleaned = strip_trailing_slash(rest)
    if cleaned == "" {
      None
    } else {
      Some("https://\{cleaned}/")
    }
  } else {
    let cleaned = strip_trailing_slash(trimmed)
    if cleaned == "" {
      None
    } else {
      Some("https://\{cleaned}/")
    }
  }
}

///|
/// Convert a config entry into an account: requires non-empty string
/// `host` and `login`, and a normalizable origin.
pub fn to_github_copilot_account(value~ : Json) -> GitHubCopilotAccount? {
  guard value is Object(fields) else { return None }
  let host = match fields.get("host") {
    Some(String(host)) if host != "" => host
    _ => return None
  }
  let login = match fields.get("login") {
    Some(String(login)) if login != "" => login
    _ => return None
  }
  match normalize_github_host(host) {
    Some(normalized) => Some({ host: normalized, login, })
    None => None
  }
}

///|
/// Select the Copilot account from a parsed CLI config: `last_logged_in_user`
/// (and its camelCase alias) win, then the first valid entry of
/// `logged_in_users` / `loggedInUsers`.
pub fn select_github_copilot_account(config~ : Json) -> GitHubCopilotAccount? {
  guard config is Object(fields) else { return None }
  for key in ["last_logged_in_user", "lastLoggedInUser"] {
    match fields.get(key) {
      Some(value) =>
        match to_github_copilot_account(value~) {
          Some(account) => return Some(account)
          None => ()
        }
      None => ()
    }
  }
  for key in ["logged_in_users", "loggedInUsers"] {
    match fields.get(key) {
      Some(Array(values)) =>
        for value in values {
          match to_github_copilot_account(value~) {
            Some(account) => return Some(account)
            None => ()
          }
        }
      _ => ()
    }
  }
  None
}

///|
/// Read the plaintext Copilot token for an account key from
/// `config.copilotTokens[accountKey]`.
pub fn get_plaintext_copilot_token(
  config~ : Json,
  account_key~ : String,
) -> String? {
  match config {
    Object(fields) =>
      match fields.get("copilotTokens") {
        Some(Object(tokens)) =>
          match tokens.get(account_key) {
            Some(String(token)) if token != "" => Some(token)
            _ => None
          }
        _ => None
      }
    _ => None
  }
}
