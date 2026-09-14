///|
/// Version of the Moonai harness-grok-build subpackage.
pub const VERSION : String = "0.1.0"

///|
/// OAuth client id xAI's CLI uses against the Grok issuer.
pub const XAI_CLIENT_ID : String = "b1a00492-073a-47ea-816f-4c329264a828"

///|
/// Base URL the Grok subscription auth flow points the CLI at.
pub const GROK_SUBSCRIPTION_BASE_URL : String = "https://cli-chat-proxy.grok.com/v1"

///|
/// A selected Grok OAuth credential record: the access token (`key`), its
/// refresh token, and the normalized epoch-millis expiry.
pub(all) struct GrokOAuthRecord {
  scope : String
  issuer : String
  key : String
  refresh_token : String
  expires_at : Int64
} derive(Debug, Eq)

///|
/// Normalize an expires_at value: epoch seconds are scaled to millis;
/// ISO-8601 strings are parsed; anything else is rejected.
pub fn grok_normalize_expires_at(value : Json) -> Int64? {
  match value {
    Number(count, ..) => {
      let millis = count.to_int64()
      if millis < 10_000_000_000L {
        Some(millis * 1000L)
      } else {
        Some(millis)
      }
    }
    String(text) => {
      // Accept the compact "YYYY-MM-DDTHH:mm:ssZ" form used by the CLI.
      let trimmed = text.trim().to_owned()
      try {
        let year = @string.parse_int64(trimmed[0:4].to_owned(), base=10)
        let month = @string.parse_int64(trimmed[5:7].to_owned(), base=10)
        let day = @string.parse_int64(trimmed[8:10].to_owned(), base=10)
        let hour = @string.parse_int64(trimmed[11:13].to_owned(), base=10)
        let minute = @string.parse_int64(trimmed[14:16].to_owned(), base=10)
        let second = @string.parse_int64(trimmed[17:19].to_owned(), base=10)
        let days = grok_days_from_civil(
          year.to_int(),
          month.to_int(),
          day.to_int(),
        )
        let seconds = days * 86400 +
          hour.to_int() * 3600 +
          minute.to_int() * 60 +
          second.to_int()
        Some(seconds.to_int64() * 1000L)
      } catch {
        _ => None
      }
    }
    _ => None
  }
}

///|
/// Days since 1970-01-01 for a civil date (Howard Hinnant's algorithm).
fn grok_days_from_civil(year : Int, month : Int, day : Int) -> Int {
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = (month + 9) % 12
  let doy = (153 * mp + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468
}

///|
/// Find the start index of the final "::" separator in a scope key.
fn grok_last_separator(scope : String) -> Int {
  let mut index = scope.length() - 2
  while index > 0 {
    if scope[index] == ':' && scope[index + 1] == ':' {
      return index
    }
    index = index - 1
  }
  -1
}

///|
/// Select the Grok OAuth record from a parsed auth.json root. The scope key
/// must have the form `<issuer>::<XAI_CLIENT_ID>` and the record must carry
/// string `key`/`refresh_token` plus a normalizable `expires_at`.
pub fn grok_select_oauth_record(value~ : Json) -> GrokOAuthRecord? {
  match value {
    Object(fields) => {
      for scope, candidate in fields.iter2() {
        guard candidate is Object(record) else { continue }
        let key = match record.get("key") {
          Some(String(key)) => key
          _ => continue
        }
        let refresh_token = match record.get("refresh_token") {
          Some(String(token)) => token
          _ => continue
        }
        let expires_at = match record.get("expires_at") {
          Some(raw) =>
            match grok_normalize_expires_at(raw) {
              Some(normalized) => normalized
              None => continue
            }
          None => continue
        }
        let separator = grok_last_separator(scope)
        guard separator > 0 else { continue }
        if scope[separator + 2:].to_owned() == XAI_CLIENT_ID {
          return Some({
            scope,
            issuer: scope[:separator].to_owned(),
            key,
            refresh_token,
            expires_at,
          })
        }
      }
      None
    }
    _ => None
  }
}

///|
/// Decide whether the native Grok subscription should be resolved: only when
/// the auth mode is not gateway-only, no direct XAI_API_KEY credential is
/// present, and the environment carries no AI Gateway key.
pub fn should_resolve_grok_native_subscription(
  ai_gateway_auth~ : Bool,
  has_direct_credential~ : Bool,
) -> Bool {
  !ai_gateway_auth && !has_direct_credential
}
