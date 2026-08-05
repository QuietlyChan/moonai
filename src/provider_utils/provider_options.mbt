///|
/// Provider-specific request fields after namespace selection and validation.
pub(all) struct ProviderOptionsResolution {
  values : Map[String, Json]
  warnings : Array[@provider.Warning]
  namespace_key : String?
} derive(Debug)

///|
/// Stateful, schema-like reader for one resolved provider options object.
///
/// Provider packages use this reader to keep JSON validation separate from
/// request encoding. Fields that are read are tracked so compatible providers
/// can forward only genuine extension fields.
pub struct ProviderOptionsReader {
  priv values : Map[String, Json]
  priv consumed : Map[String, Bool]
  priv warnings : Array[@provider.Warning]
  priv path : String
}

///|
fn contains_string(values : Array[String], expected : String) -> Bool {
  for value in values {
    if value == expected {
      return true
    }
  }
  false
}

///|
fn add_candidate(values : Array[String], candidate : String) -> Unit {
  if candidate != "" && !contains_string(values, candidate) {
    values.push(candidate)
  }
}

///|
fn copy_json_map(values : Map[String, Json]) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for entry in values.iter2() {
    let (key, value) = entry
    result[key] = value
  }
  result
}

///|
/// Drop the model-kind suffix used by moonai provider identifiers.
fn provider_options_base_name(provider_name : String) -> String {
  let trimmed = provider_name.trim().to_owned()
  let suffixes = [
    ".responses", ".messages", ".chat", ".completion", ".embedding", ".image", ".speech",
    ".transcription", ".translation", ".files", ".skills", ".video", ".realtime",
  ]
  for suffix in suffixes {
    if trimmed.strip_suffix(suffix) is Some(base) {
      return base.to_owned()
    }
  }
  trimmed
}

///|
/// Convert provider identifiers such as `openai-compatible` to camel case.
fn provider_options_camel_case(value : String) -> String {
  let result = StringBuilder::new(size_hint=value.length())
  let mut capitalize_next = false
  for character in value {
    if character == '-' || character == '_' || character == '.' {
      capitalize_next = true
    } else if capitalize_next {
      result.write_object(character.to_ascii_uppercase())
      capitalize_next = false
    } else {
      result.write_object(character)
    }
  }
  result.to_string()
}

///|
/// Resolve the provider-metadata key paired with a provider-options namespace.
///
/// AI SDK preserves the raw provider name unless the caller selected its
/// camel-case namespace. Model-kind suffixes are ignored in both cases.
pub fn resolve_provider_options_key(
  provider_name : String,
  options : Map[String, Json],
) -> String {
  let base_name = provider_options_base_name(provider_name)
  let camel_name = provider_options_camel_case(base_name)
  if camel_name != base_name {
    match options.get(camel_name) {
      Some(Null) | None => base_name
      Some(_) => camel_name
    }
  } else {
    base_name
  }
}

///|
/// Resolve provider options using the AI SDK provider namespace convention.
///
/// Camel-case provider keys take precedence. Protocol-owned fields are removed
/// so extensions cannot change the selected model, prompt, or transport mode
/// behind the normalized API.
pub fn resolve_provider_options(
  options : Map[String, Json],
  provider_name? : String = "",
  aliases? : Array[String] = [],
  reserved_fields? : Array[String] = [],
  prefer_exact_provider_name? : Bool = false,
) -> ProviderOptionsResolution {
  let warnings : Array[@provider.Warning] = []
  let base_name = provider_options_base_name(provider_name)
  let camel_name = provider_options_camel_case(base_name)
  let candidates : Array[String] = []
  if prefer_exact_provider_name {
    add_candidate(candidates, base_name)
    add_candidate(candidates, camel_name)
  } else {
    add_candidate(candidates, camel_name)
    add_candidate(candidates, base_name)
  }
  for alternative in aliases {
    add_candidate(candidates, provider_options_camel_case(alternative))
    add_candidate(candidates, alternative)
  }
  let mut selected_name = ""
  let mut invalid_namespace = ""
  let mut scoped_values : Map[String, Json]? = None
  for candidate in candidates {
    match options.get(candidate) {
      Some(Object(values)) => {
        selected_name = candidate
        scoped_values = Some(values)
        break
      }
      Some(_) => invalid_namespace = candidate
      None => ()
    }
  }
  let source = match scoped_values {
    Some(values) => {
      if !prefer_exact_provider_name &&
        selected_name == base_name &&
        base_name != camel_name {
        warnings.push(
          @provider.Warning::Deprecated(
            setting="provider_options key '\{base_name}'",
            message="Use the camel-case key '\{camel_name}'.",
          ),
        )
      }
      values
    }
    None if invalid_namespace != "" => {
      warnings.push(
        @provider.Warning::Other(
          message="provider_options namespace '\{invalid_namespace}' must contain a JSON object",
        ),
      )
      Map([])
    }
    None => Map([])
  }
  let values : Map[String, Json] = Map([])
  for entry in source.iter2() {
    let (key, value) = entry
    if contains_string(reserved_fields, key) {
      warnings.push(
        @provider.Warning::Compatibility(
          feature="providerOptions.\{key}",
          details="Ignored because '\{key}' is owned by the normalized request.",
        ),
      )
    } else {
      values[key] = value
    }
  }
  {
    values,
    warnings,
    namespace_key: if selected_name == "" {
      None
    } else {
      Some(selected_name)
    },
  }
}

///|
/// Merge two resolved option layers. Values and diagnostics from `overrides`
/// are appended after `base`, matching provider-default then custom-provider
/// precedence in the AI SDK.
pub fn merge_provider_options_resolutions(
  base : ProviderOptionsResolution,
  overrides : ProviderOptionsResolution,
) -> ProviderOptionsResolution {
  let values = copy_json_map(base.values)
  for entry in overrides.values.iter2() {
    let (key, value) = entry
    values[key] = value
  }
  let warnings = base.warnings.copy()
  for warning in overrides.warnings {
    warnings.push(warning)
  }
  {
    values,
    warnings,
    namespace_key: match overrides.namespace_key {
      Some(_) => overrides.namespace_key
      None => base.namespace_key
    },
  }
}

///|
/// Create a typed reader from a resolved provider namespace.
pub fn ProviderOptionsReader::new(
  resolution : ProviderOptionsResolution,
  path? : String = "providerOptions",
) -> ProviderOptionsReader {
  {
    values: copy_json_map(resolution.values),
    consumed: Map([]),
    warnings: resolution.warnings.copy(),
    path,
  }
}

///|
fn ProviderOptionsReader::field_path(
  self : ProviderOptionsReader,
  field : String,
) -> String {
  if self.path == "" {
    field
  } else {
    "\{self.path}.\{field}"
  }
}

///|
fn ProviderOptionsReader::take_value(
  self : ProviderOptionsReader,
  field : String,
  aliases : Array[String],
) -> Json? {
  let mut selected_key = ""
  let mut selected : Json? = None
  match self.values.get(field) {
    Some(value) => {
      selected_key = field
      selected = Some(value)
    }
    None =>
      for alternative in aliases {
        if self.values.get(alternative) is Some(value) {
          selected_key = alternative
          selected = Some(value)
          break
        }
      }
  }
  if selected_key != "" {
    self.consumed[selected_key] = true
    if selected_key != field {
      self.warnings.push(
        @provider.Warning::Deprecated(
          setting=self.field_path(selected_key),
          message="Use '\{self.field_path(field)}'.",
        ),
      )
    }
  }
  for alternative in aliases {
    if self.values.get(alternative) is Some(_) {
      self.consumed[alternative] = true
    }
  }
  selected
}

///|
fn ProviderOptionsReader::invalid_type(
  self : ProviderOptionsReader,
  field : String,
  expected : String,
) -> Unit {
  self.warnings.push(
    @provider.Warning::Compatibility(
      feature=self.field_path(field),
      details="Expected \{expected}; the invalid value was ignored.",
    ),
  )
}

///|
/// Convert a JSON number to `Int` only when it is exactly representable.
pub fn json_number_as_int(number : Double) -> Int? {
  let value = number.to_int()
  if value.to_double() == number {
    Some(value)
  } else {
    None
  }
}

///|
/// Add a provider-specific validation warning to this reader.
pub fn ProviderOptionsReader::add_warning(
  self : ProviderOptionsReader,
  warning : @provider.Warning,
) -> Unit {
  self.warnings.push(warning)
}

///|
/// Consume any non-null JSON value without applying a shape constraint.
pub fn ProviderOptionsReader::take_json(
  self : ProviderOptionsReader,
  field : String,
  aliases? : Array[String] = [],
) -> Json? {
  match self.take_value(field, aliases) {
    Some(Null) | None => None
    value => value
  }
}

///|
/// Consume a string option, optionally restricting it to an allowlist.
pub fn ProviderOptionsReader::take_string(
  self : ProviderOptionsReader,
  field : String,
  aliases? : Array[String] = [],
  allowed? : Array[String] = [],
) -> String? {
  match self.take_value(field, aliases) {
    Some(String(value)) =>
      if allowed.length() == 0 || contains_string(allowed, value) {
        Some(value)
      } else {
        self.invalid_type(field, "one of [\{allowed.join(", ")}]")
        None
      }
    Some(Null) | None => None
    Some(_) => {
      self.invalid_type(field, "a string")
      None
    }
  }
}

///|
/// Consume a boolean option.
pub fn ProviderOptionsReader::take_bool(
  self : ProviderOptionsReader,
  field : String,
  aliases? : Array[String] = [],
) -> Bool? {
  match self.take_value(field, aliases) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    Some(Null) | None => None
    Some(_) => {
      self.invalid_type(field, "a boolean")
      None
    }
  }
}

///|
/// Consume an integer option and enforce optional inclusive bounds.
pub fn ProviderOptionsReader::take_int(
  self : ProviderOptionsReader,
  field : String,
  aliases? : Array[String] = [],
  min? : Int,
  max? : Int,
) -> Int? {
  match self.take_value(field, aliases) {
    Some(Number(number, ..)) => {
      guard json_number_as_int(number) is Some(value) else {
        self.invalid_type(field, "an integer")
        return None
      }
      if min is Some(lower) && value < lower {
        self.invalid_type(field, "an integer greater than or equal to \{lower}")
        None
      } else if max is Some(upper) && value > upper {
        self.invalid_type(field, "an integer less than or equal to \{upper}")
        None
      } else {
        Some(value)
      }
    }
    Some(Null) | None => None
    Some(_) => {
      self.invalid_type(field, "an integer")
      None
    }
  }
}

///|
/// Consume a numeric option and enforce optional inclusive bounds.
pub fn ProviderOptionsReader::take_double(
  self : ProviderOptionsReader,
  field : String,
  aliases? : Array[String] = [],
  min? : Double,
  max? : Double,
) -> Double? {
  match self.take_value(field, aliases) {
    Some(Number(value, ..)) =>
      if min is Some(lower) && value < lower {
        self.invalid_type(field, "a number greater than or equal to \{lower}")
        None
      } else if max is Some(upper) && value > upper {
        self.invalid_type(field, "a number less than or equal to \{upper}")
        None
      } else {
        Some(value)
      }
    Some(Null) | None => None
    Some(_) => {
      self.invalid_type(field, "a number")
      None
    }
  }
}

///|
/// Consume an object option.
pub fn ProviderOptionsReader::take_object(
  self : ProviderOptionsReader,
  field : String,
  aliases? : Array[String] = [],
) -> Map[String, Json]? {
  match self.take_value(field, aliases) {
    Some(Object(value)) => Some(copy_json_map(value))
    Some(Null) | None => None
    Some(_) => {
      self.invalid_type(field, "an object")
      None
    }
  }
}

///|
/// Consume an array option.
pub fn ProviderOptionsReader::take_array(
  self : ProviderOptionsReader,
  field : String,
  aliases? : Array[String] = [],
) -> Array[Json]? {
  match self.take_value(field, aliases) {
    Some(Array(value)) => Some(value.copy())
    Some(Null) | None => None
    Some(_) => {
      self.invalid_type(field, "an array")
      None
    }
  }
}

///|
/// Return fields that were not consumed by the typed schema.
pub fn ProviderOptionsReader::remaining_values(
  self : ProviderOptionsReader,
) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for entry in self.values.iter2() {
    let (key, value) = entry
    if self.consumed.get(key) is None {
      result[key] = value
    }
  }
  result
}

///|
/// Return accumulated namespace and field validation warnings.
pub fn ProviderOptionsReader::diagnostics(
  self : ProviderOptionsReader,
) -> Array[@provider.Warning] {
  self.warnings.copy()
}
