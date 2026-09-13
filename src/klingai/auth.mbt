///|
/// Resolve the bearer token for KlingAI API requests. Two schemes:
/// 1. a direct API key (`KLINGAI_API_KEY`), or
/// 2. a legacy access/secret key pair (`KLINGAI_ACCESS_KEY` +
///    `KLINGAI_SECRET_KEY`) signed into a short-lived HS256 JWT
///    (iss=access key, exp now+30min, nbf now-5s).
pub fn resolve_klingai_auth_token(
  api_key? : String,
  access_key? : String,
  secret_key? : String,
) -> String raise @provider.LoadAPIKeyError {
  if api_key is Some(key) && key.trim() != "" {
    return key
  }
  let ak = @provider_utils.load_optional_setting(
    access_key,
    environment_variable_name="KLINGAI_ACCESS_KEY",
  )
  let sk = @provider_utils.load_optional_setting(
    secret_key,
    environment_variable_name="KLINGAI_SECRET_KEY",
  )
  match (ak, sk) {
    (Some(ak), Some(sk)) if ak.trim() != "" && sk.trim() != "" =>
      klingai_jwt(ak.trim().to_owned(), sk.trim().to_owned())
    _ =>
      raise @provider.LoadAPIKeyError(
        environment_variable_name="KLINGAI_API_KEY",
        api_key_parameter_name="api_key",
        description="KlingAI",
        message="KlingAI requires either an API key (KLINGAI_API_KEY) or an access/secret key pair (KLINGAI_ACCESS_KEY + KLINGAI_SECRET_KEY).",
      )
  }
}

///|
/// Build a KlingAI HS256 JWT: header {alg: HS256, typ: JWT}, payload
/// {iss: access key, exp: now+1800, nbf: now-5}.
fn klingai_jwt(ak : String, sk : String) -> String {
  let now = (@env.now() / 1000UL).reinterpret_as_int64()
  let header = base64url_of_json("{ \"alg\": \"HS256\", \"typ\": \"JWT\" }")
  let payload = base64url_of_json(
    "{ \"iss\": \"\{ak}\", \"exp\": \{now + 1800}, \"nbf\": \{now - 5} }",
  )
  let signing_input = "\{header}.\{payload}"
  let signature = base64url(
    @base64.encode(
      @mooncry.hmac_sha256(@utf8enc.encode(sk), @utf8enc.encode(signing_input)),
      padding=false,
    ),
  )
  "\{signing_input}.\{signature}"
}

///|
fn base64url_of_json(text : String) -> String {
  base64url(@base64.encode(@utf8enc.encode(text), padding=false))
}

///|
/// Convert standard Base64 to Base64url (URL-safe, unpadded).
fn base64url(value : String) -> String {
  let result = StringBuilder()
  for character in value {
    match character {
      '+' => result.write_char('-')
      '/' => result.write_char('_')
      '=' => ()
      c => result.write_char(c)
    }
  }
  result.to_string()
}
