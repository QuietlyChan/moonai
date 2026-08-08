///|
/// Result of validating a JSON value without raising.
pub(all) enum TypeValidationResult[T] {
  TypeValidationSuccess(value~ : T, raw_value~ : Json)
  TypeValidationFailure(
    error~ : @provider.TypeValidationError,
    raw_value~ : Json
  )
}

///|
/// Result of parsing and optionally validating JSON without raising.
pub(all) enum ParseJsonResult[T] {
  ParseJsonSuccess(value~ : T, raw_value~ : Json)
  ParseJsonFailure(error~ : @provider.JSONParseError, raw_value~ : Json?)
  ParseJsonValidationFailure(
    error~ : @provider.TypeValidationError,
    raw_value~ : Json
  )
}

///|
/// Parse JSON and preserve the original input in a typed parse error.
pub fn parse_json(text : String) -> Json raise @provider.JSONParseError {
  @json.parse(text) catch {
    error =>
      raise @provider.JSONParseError::new(text~, cause=@debug.to_string(error))
  }
}

///|
/// AI SDK-style spelling for `parse_json`.
pub fn parseJSON(text : String) -> Json raise @provider.JSONParseError {
  parse_json(text)
}

///|
/// Validate a JSON value and wrap callback failures in `TypeValidationError`.
pub fn[T] validate_types(
  value : Json,
  validator : (Json) -> T raise,
  context? : @provider.TypeValidationContext,
) -> T raise @provider.TypeValidationError {
  validator(value) catch {
    @provider.TypeValidationError(
      value=existing_value,
      cause~,
      context=existing_context
    ) => {
      let existing = @provider.TypeValidationError(
        value=existing_value,
        cause~,
        context=existing_context,
      )
      if existing_value == value && existing_context == context {
        raise existing
      }
      raise @provider.TypeValidationError::new(
        value~,
        cause=existing.message(),
        context?,
      )
    }
    error =>
      raise @provider.TypeValidationError::new(
        value~,
        cause=@debug.to_string(error),
        context?,
      )
  }
}

///|
/// AI SDK-style spelling for `validate_types`.
pub fn[T] validateTypes(
  value : Json,
  validator : (Json) -> T raise,
  context? : @provider.TypeValidationContext,
) -> T raise @provider.TypeValidationError {
  validate_types(value, validator, context?)
}

///|
/// Validate a JSON value without raising.
pub fn[T] safe_validate_types(
  value : Json,
  validator : (Json) -> T raise,
  context? : @provider.TypeValidationContext,
) -> TypeValidationResult[T] {
  try validate_types(value, validator, context?) catch {
    @provider.TypeValidationError(value~, cause~, context~) =>
      TypeValidationFailure(
        error=@provider.TypeValidationError(value~, cause~, context~),
        raw_value=value,
      )
  } noraise {
    result => TypeValidationSuccess(value=result, raw_value=value)
  }
}

///|
/// AI SDK-style spelling for `safe_validate_types`.
pub fn[T] safeValidateTypes(
  value : Json,
  validator : (Json) -> T raise,
  context? : @provider.TypeValidationContext,
) -> TypeValidationResult[T] {
  safe_validate_types(value, validator, context?)
}

///|
/// Parse JSON and validate the parsed value through one typed boundary.
pub fn[T] parse_json_with(
  text : String,
  validator : (Json) -> T raise,
  context? : @provider.TypeValidationContext,
) -> T raise {
  validate_types(parse_json(text), validator, context?)
}

///|
/// AI SDK-style spelling for `parse_json_with`.
pub fn[T] parseJSONWith(
  text : String,
  validator : (Json) -> T raise,
  context? : @provider.TypeValidationContext,
) -> T raise {
  parse_json_with(text, validator, context?)
}

///|
/// Parse JSON without raising.
pub fn safe_parse_json(text : String) -> ParseJsonResult[Json] {
  try parse_json(text) catch {
    @provider.JSONParseError(text~, cause~) =>
      ParseJsonFailure(
        error=@provider.JSONParseError(text~, cause~),
        raw_value=None,
      )
  } noraise {
    value => ParseJsonSuccess(value~, raw_value=value)
  }
}

///|
/// AI SDK-style spelling for `safe_parse_json`.
pub fn safeParseJSON(text : String) -> ParseJsonResult[Json] {
  safe_parse_json(text)
}

///|
/// Parse and validate JSON without raising.
pub fn[T] safe_parse_json_with(
  text : String,
  validator : (Json) -> T raise,
  context? : @provider.TypeValidationContext,
) -> ParseJsonResult[T] {
  match safe_parse_json(text) {
    ParseJsonSuccess(value=raw_value, ..) =>
      match safe_validate_types(raw_value, validator, context?) {
        TypeValidationSuccess(value~, ..) =>
          ParseJsonSuccess(value~, raw_value~)
        TypeValidationFailure(error~, ..) =>
          ParseJsonValidationFailure(error~, raw_value~)
      }
    ParseJsonFailure(error~, raw_value~) => ParseJsonFailure(error~, raw_value~)
    ParseJsonValidationFailure(error~, raw_value~) =>
      ParseJsonValidationFailure(error~, raw_value~)
  }
}

///|
/// AI SDK-style spelling for `safe_parse_json_with`.
pub fn[T] safeParseJSONWith(
  text : String,
  validator : (Json) -> T raise,
  context? : @provider.TypeValidationContext,
) -> ParseJsonResult[T] {
  safe_parse_json_with(text, validator, context?)
}

///|
/// Return whether a string contains syntactically valid JSON.
pub fn is_parsable_json(text : String) -> Bool {
  safe_parse_json(text) is ParseJsonSuccess(..)
}

///|
/// AI SDK-style spelling for `is_parsable_json`.
pub fn isParsableJson(text : String) -> Bool {
  is_parsable_json(text)
}

///|
/// Parse opportunistically when a protocol permits non-JSON fallback bodies.
fn parse_json_if_valid(text : String) -> Json? {
  match safe_parse_json(text) {
    ParseJsonSuccess(value~, ..) => Some(value)
    _ => None
  }
}
