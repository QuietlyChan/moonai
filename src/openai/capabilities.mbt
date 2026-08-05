///|
priv struct OpenAIGptVersion {
  major : Int
  minor : Int?
  variant : String?
}

///|
/// Request compatibility flags for one official OpenAI language model.
priv struct OpenAILanguageModelCapabilities {
  is_reasoning_model : Bool
  system_message_mode : String
  supports_flex_processing : Bool
  supports_priority_processing : Bool
  supports_non_reasoning_parameters : Bool
}

///|
fn parse_int_opt(value : StringView) -> Int? {
  try @string.parse_int(value) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn openai_o_series_version(model_id : String) -> Int? {
  guard model_id.strip_prefix("o") is Some(rest) else { return None }
  let parts = [ for part in rest.to_owned().split("-") => part ]
  guard parts.length() > 0 else { return None }
  parse_int_opt(parts[0])
}

///|
fn openai_gpt_version(model_id : String) -> OpenAIGptVersion? {
  guard model_id.strip_prefix("gpt-") is Some(rest) else { return None }
  let dash_parts = [ for part in rest.to_owned().split("-") => part ]
  guard dash_parts.length() > 0 else { return None }
  let version_parts = [
    for part in dash_parts[0].to_owned().split(".") => part
  ]
  guard version_parts.length() > 0 else { return None }
  guard parse_int_opt(version_parts[0]) is Some(major) else { return None }
  let minor = if version_parts.length() > 1 {
    parse_int_opt(version_parts[1])
  } else {
    None
  }
  let variant = if dash_parts.length() > 1 {
    Some(dash_parts[1].to_owned())
  } else {
    None
  }
  Some({ major, minor, variant })
}

///|
/// Resolve OpenAI reasoning, role, and service-tier behavior from the model ID.
fn get_openai_language_model_capabilities(
  model_id : String,
) -> OpenAILanguageModelCapabilities {
  let o_series_version = openai_o_series_version(model_id)
  let gpt_version = openai_gpt_version(model_id)
  let is_gpt_chat_model = match gpt_version {
    Some({ minor: None, variant: Some(value), .. }) => value.has_prefix("chat")
    _ => false
  }
  let is_gpt_nano_model = match gpt_version {
    Some({ variant: Some(value), .. }) => value.has_prefix("nano")
    _ => false
  }
  let supports_flex_processing = match (o_series_version, gpt_version) {
    (Some(version), _) if version >= 3 => true
    (_, Some(version)) if version.major >= 5 && !is_gpt_chat_model => true
    _ => false
  }
  let supports_priority_processing = model_id.has_prefix("gpt-4") ||
    (match (o_series_version, gpt_version) {
      (Some(version), _) if version >= 3 => true
      (_, Some(version)) if version.major >= 5 &&
        !is_gpt_nano_model &&
        !is_gpt_chat_model => true
      _ => false
    })
  let is_reasoning_model = o_series_version is Some(_) ||
    (match gpt_version {
      Some(version) => version.major >= 5 && !is_gpt_chat_model
      None => false
    })
  let supports_non_reasoning_parameters = match gpt_version {
    Some(version) =>
      version.major > 5 ||
      (version.major == 5 && version.minor.unwrap_or(0) >= 1)
    None => false
  }
  {
    is_reasoning_model,
    system_message_mode: if is_reasoning_model {
      "developer"
    } else {
      "system"
    },
    supports_flex_processing,
    supports_priority_processing,
    supports_non_reasoning_parameters,
  }
}
