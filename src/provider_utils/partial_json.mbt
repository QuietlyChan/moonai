///|
/// Outcome of parsing a possibly-truncated JSON prefix.
pub(all) enum PartialJsonParseState {
  /// The input was empty or whitespace only.
  PartialUndefinedInput
  /// The input was a complete, valid JSON value.
  PartialSuccessfulParse
  /// The input was truncated and repaired by closing the open string and
  /// all open containers (dropping the trailing incomplete token).
  PartialSuccessfulRepair
  /// The input could not be repaired into valid JSON.
  PartialFailedParse
} derive(Debug, Eq)

///|
/// Result of parsing a possibly-truncated JSON prefix.
pub(all) struct PartialJsonResult {
  value : Json
  state : PartialJsonParseState
} derive(Debug, Eq)

///|
fn unwrap_or_null(value : Json?) -> Json {
  match value {
    Some(json) => json
    None => Json::string("")
  }
}

///|
/// Scanner state for one JSON prefix.
priv struct PartialScanState {
  stack : Array[Byte]
  mut in_string : Bool
  mut escaped : Bool
  mut in_token : Bool
  mut token_start : Int
  /// True once a colon (or an array comma) has been consumed and a value is
  /// expected next.
  mut awaiting_value : Bool
  /// True when the currently open string is an object key.
  mut string_is_key : Bool
}

///|
fn partial_scan_new() -> PartialScanState {
  {
    stack: [],
    in_string: false,
    escaped: false,
    in_token: false,
    token_start: -1,
    awaiting_value: false,
    string_is_key: false,
  }
}

///|
/// Feed one byte to the scanner. 34 is the JSON string quote, 92 the
/// backslash; delimiters (44 comma, 58 colon, whitespace) end bare tokens.
fn partial_scan_feed(
  state : PartialScanState,
  offset : Int,
  byte : Byte,
) -> Unit {
  if state.in_string {
    if state.escaped {
      state.escaped = false
    } else if byte == 92 {
      state.escaped = true
    } else if byte == 34 {
      state.in_string = false
      state.escaped = false
    }
    return
  }
  match byte {
    34 => {
      state.in_string = true
      state.escaped = false
      // Inside an object before the colon this string is a key.
      state.string_is_key = state.stack.last() == Some(123) &&
        !state.awaiting_value
    }
    123 => {
      state.stack.push(123)
      state.awaiting_value = false
      state.in_token = false
    }
    91 => {
      state.stack.push(91)
      state.awaiting_value = false
      state.in_token = false
    }
    125 | 93 => {
      let _ = state.stack.pop()
      state.awaiting_value = false
      state.in_token = false
    }
    58 => {
      state.awaiting_value = true
      state.in_token = false
    }
    44 => {
      state.awaiting_value = false
      state.in_token = false
    }
    32 | 9 | 13 | 10 => state.in_token = false
    _ =>
      if !state.in_token {
        state.in_token = true
        state.token_start = offset
      }
  }
}

///|
/// Build the repaired text for the prefix [0, end): close an open string,
/// complete or drop a trailing bare token, trim a dangling comma, and close
/// all open containers.
fn repair_partial_prefix(bytes : Bytes, end : Int) -> String? {
  let state = partial_scan_new()
  for index = 0; index < end; index = index + 1 {
    partial_scan_feed(state, index, bytes[index])
  }
  let closers = StringBuilder()
  for open in state.stack {
    closers.write_string(if open == 123 { "}" } else { "]" })
  }
  let mut cut = end
  let mut tail = closers.to_string()
  if state.in_string {
    // Close the string; when it is an object key the value is still missing.
    if state.string_is_key && state.stack.last() == Some(123) {
      tail = "\": null" + closers.to_string()
    } else {
      tail = "\"" + closers.to_string()
    }
    let prefix = @utf8.decode_lossy(bytes[0:end])
    return Some(prefix + tail)
  }
  if state.in_token {
    let token = bytes[state.token_start:end]
    let first = token[0]
    let is_complete_number = (first >= 48 && first <= 57) || first == 45
    let is_full_literal = token == b"true" ||
      token == b"false" ||
      token == b"null"
    let last_byte = bytes[end - 1]
    let token_text = @utf8.decode_lossy(token)
    let literal_prefix = "true".starts_with(token_text) ||
      "false".starts_with(token_text) ||
      "null".starts_with(token_text)
    let is_number_incomplete = is_complete_number &&
      (
        last_byte == 46 ||
        last_byte == 101 ||
        last_byte == 69 ||
        last_byte == 45 ||
        last_byte == 43
      )
    if (is_complete_number && !is_number_incomplete) || is_full_literal {
      // Keep the token as-is; the closers terminate it.
    } else if literal_prefix {
      // Replace the partial literal with its complete form.
      cut = state.token_start
      let completion = if "true".starts_with(token_text) {
        "true"
      } else if "false".starts_with(token_text) {
        "false"
      } else {
        "null"
      }
      let prefix = @utf8.decode_lossy(bytes[0:end])
      return Some(prefix + completion + closers.to_string())
    } else if state.awaiting_value {
      // Drop the truncated token; the colon is still pending a value.
      cut = state.token_start
      tail = " null" + closers.to_string()
      let prefix = @utf8.decode_lossy(bytes[0:cut])
      return Some(prefix + tail)
    } else {
      // Drop the trailing token along with its dangling comma.
      cut = state.token_start
      while cut > 0 {
        let byte = bytes[cut - 1]
        if byte == 44 || byte == 32 || byte == 9 || byte == 13 || byte == 10 {
          cut = cut - 1
        } else {
          break
        }
      }
    }
  }
  let prefix = @utf8.decode_lossy(bytes[0:cut])
  Some(prefix + tail)
}

///|
/// Parse a possibly-truncated JSON prefix, tolerating incomplete strings,
/// containers, and trailing tokens.
///
/// - A complete value parses as `PartialSuccessfulParse`.
/// - A truncated value is repaired by completing or dropping the trailing
///   token and closing the open string and containers
///   (`PartialSuccessfulRepair`).
/// - Empty input yields `PartialUndefinedInput` with a null value.
/// - Input that cannot be repaired yields `PartialFailedParse` with an empty
///   string value.
///
/// This is the MoonBit counterpart of AI SDK's `parsePartialJson`, the
/// foundation for streaming partial objects.
pub fn parse_partial_json(text : String) -> PartialJsonResult {
  let trimmed = text.trim().to_owned()
  if trimmed.is_empty() {
    return {
      value: unwrap_or_null(parse_json_if_valid("null")),
      state: PartialUndefinedInput,
    }
  }
  match parse_json_if_valid(trimmed) {
    Some(value) => return { value, state: PartialSuccessfulParse, }
    None => ()
  }
  let bytes = @utf8.encode(trimmed)
  // Repair over the whole input, then progressively shorter prefixes.
  let mut end = bytes.length()
  while end > 0 {
    match repair_partial_prefix(bytes, end) {
      Some(repaired) =>
        match parse_json_if_valid(repaired) {
          Some(value) => return { value, state: PartialSuccessfulRepair, }
          None => ()
        }
      None => ()
    }
    end = end - 1
  }
  { value: Json::string(""), state: PartialFailedParse, }
}
