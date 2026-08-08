///|
/// Secret material used to sign tool approval requests.
///
/// The string form is encoded as UTF-8. The bytes form preserves the exact
/// key material, matching the AI SDK's `string | Uint8Array` option.
pub(all) enum ToolApprovalSecret {
  ToolApprovalSecretString(String)
  ToolApprovalSecretBytes(Bytes)
} derive(Debug, Eq)

///|
/// Construct a tool approval secret from UTF-8 text.
pub fn ToolApprovalSecret::string(value : String) -> ToolApprovalSecret {
  ToolApprovalSecretString(value)
}

///|
/// Construct a tool approval secret from raw bytes.
pub fn ToolApprovalSecret::bytes(value : Bytes) -> ToolApprovalSecret {
  ToolApprovalSecretBytes(value)
}

///|
fn ToolApprovalSecret::to_bytes(self : ToolApprovalSecret) -> Bytes {
  match self {
    ToolApprovalSecretString(value) => @utf8.encode(value)
    ToolApprovalSecretBytes(value) => value
  }
}

///|
fn compare_canonical_json_keys(left : String, right : String) -> Int {
  let shared_length = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  for index in 0..<shared_length {
    if left[index] < right[index] {
      return -1
    }
    if left[index] > right[index] {
      return 1
    }
  }
  if left.length() < right.length() {
    -1
  } else if left.length() > right.length() {
    1
  } else {
    0
  }
}

///|
fn javascript_json_number_value(number : Double, repr : String?) -> Double {
  guard repr is Some(repr) else { return number }
  let decimal_repr = StringBuilder::new()
  let mut has_decimal_point = false
  let mut inserted_decimal_point = false
  for character in repr {
    match character {
      '.' => {
        has_decimal_point = true
        decimal_repr.write_char(character)
      }
      'e' | 'E' => {
        if !has_decimal_point {
          decimal_repr.write_string(".0")
          inserted_decimal_point = true
        }
        decimal_repr.write_char(character)
      }
      _ => decimal_repr.write_char(character)
    }
  }
  if !has_decimal_point && !inserted_decimal_point {
    decimal_repr.write_string(".0")
  }
  let parsed = @json.parse(decimal_repr.to_string()) catch {
    _ => return number
  }
  match parsed {
    Number(parsed_number, ..) => parsed_number
    _ => number
  }
}

///|
fn canonical_json(value : Json) -> String {
  match value {
    Object(fields) => {
      let keys = [ for entry in fields.iter2() => entry.0 ]
      keys.sort_by(compare_canonical_json_keys)
      let result = StringBuilder::new()
      result.write_char('{')
      for index, key in keys {
        if index > 0 {
          result.write_char(',')
        }
        result.write_string(Json::string(key).stringify())
        result.write_char(':')
        match fields.get(key) {
          Some(field) => result.write_string(canonical_json(field))
          None => ()
        }
      }
      result.write_char('}')
      result.to_string()
    }
    Array(values) => {
      let result = StringBuilder::new()
      result.write_char('[')
      for index, item in values {
        if index > 0 {
          result.write_char(',')
        }
        result.write_string(canonical_json(item))
      }
      result.write_char(']')
      result.to_string()
    }
    Number(number, repr~) => {
      let normalized = javascript_json_number_value(number, repr)
      if normalized.is_inf() || normalized.is_nan() {
        "null"
      } else {
        Json::number(normalized).stringify()
      }
    }
    _ => value.stringify()
  }
}

///|
fn to_base64url(value : Bytes) -> String {
  let result = StringBuilder::new()
  for character in @base64.encode(value, padding=false) {
    match character {
      '+' => result.write_char('-')
      '/' => result.write_char('_')
      _ => result.write_char(character)
    }
  }
  result.to_string()
}

///|
fn from_base64url(value : String) -> Bytes raise {
  let result = StringBuilder::new()
  for character in value {
    match character {
      '-' => result.write_char('+')
      '_' => result.write_char('/')
      ' ' | '\t' | '\n' | '\r' => ()
      _ => result.write_char(character)
    }
  }
  let normalized = result.to_string()
  let padded = match normalized.length() % 4 {
    0 => normalized
    2 => normalized + "=="
    3 => normalized + "="
    _ => fail("invalid Base64url data")
  }
  @base64.decode(padded)
}

///|
fn hash_canonical(value : Json) -> String {
  canonical_json(value) |> @utf8.encode |> @mooncry.sha256 |> to_base64url
}

///|
fn approval_signature_payload(
  approval_id : String,
  tool_call_id : String,
  tool_name : String,
  input_digest : String,
) -> Bytes {
  Json::array([
    Json::string("ai-sdk-tool-approval-v1"),
    Json::string(approval_id),
    Json::string(tool_call_id),
    Json::string(tool_name),
    Json::string(input_digest),
  ]).stringify()
  |> @utf8.encode
}

///|
fn legacy_approval_signature_payload(
  approval_id : String,
  tool_call_id : String,
  tool_name : String,
  input_digest : String,
) -> Bytes {
  @utf8.encode("\{approval_id}\n\{tool_call_id}\n\{tool_name}\n\{input_digest}")
}

///|
fn constant_time_bytes_equal(left : Bytes, right : Bytes) -> Bool {
  guard left.length() == right.length() else { return false }
  let mut difference = 0
  for index in 0..<left.length() {
    difference = difference | (left[index].to_int() ^ right[index].to_int())
  }
  difference == 0
}

///|
fn sign_tool_approval(
  secret : ToolApprovalSecret,
  approval_id : String,
  tool_call_id : String,
  tool_name : String,
  input : Json,
) -> String {
  let input_digest = hash_canonical(input)
  @mooncry.hmac_sha256(
    secret.to_bytes(),
    approval_signature_payload(
      approval_id, tool_call_id, tool_name, input_digest,
    ),
  )
  |> to_base64url
}

///|
fn maybe_sign_tool_approval(
  secret : ToolApprovalSecret?,
  approval_id : String,
  tool_call_id : String,
  tool_name : String,
  input : Json,
) -> String? {
  match secret {
    None => None
    Some(secret) =>
      Some(
        sign_tool_approval(secret, approval_id, tool_call_id, tool_name, input),
      )
  }
}

///|
fn verify_tool_approval_signature(
  secret : ToolApprovalSecret,
  signature : String,
  approval_id : String,
  tool_call_id : String,
  tool_name : String,
  input : Json,
) -> Bool {
  let signature_bytes = from_base64url(signature) catch { _ => return false }
  let key = secret.to_bytes()
  let input_digest = hash_canonical(input)
  let expected = @mooncry.hmac_sha256(
    key,
    approval_signature_payload(
      approval_id, tool_call_id, tool_name, input_digest,
    ),
  )
  if constant_time_bytes_equal(signature_bytes, expected) {
    return true
  }
  guard !approval_id.contains("\n") &&
    !tool_call_id.contains("\n") &&
    !tool_name.contains("\n") else {
    return false
  }
  constant_time_bytes_equal(
    signature_bytes,
    @mooncry.hmac_sha256(
      key,
      legacy_approval_signature_payload(
        approval_id, tool_call_id, tool_name, input_digest,
      ),
    ),
  )
}

///|
fn validate_tool_approval_signature(
  secret : ToolApprovalSecret?,
  request : @provider_utils.ModelToolApprovalRequest,
  tool_call : GenerateTextToolCall,
) -> Unit raise {
  guard secret is Some(secret) else { return }
  guard request.signature is Some(signature) else {
    raise InvalidToolApprovalSignatureError(
      approval_id=request.approval_id,
      tool_call_id=tool_call.tool_call_id,
      reason="missing signature",
    )
  }
  guard verify_tool_approval_signature(
    secret,
    signature,
    request.approval_id,
    tool_call.tool_call_id,
    tool_call.tool_name,
    tool_call.input,
  ) else {
    raise InvalidToolApprovalSignatureError(
      approval_id=request.approval_id,
      tool_call_id=tool_call.tool_call_id,
      reason="invalid signature",
    )
  }
}
