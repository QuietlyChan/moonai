///|
/// Load a required API key from an explicit value or an environment variable.
///
/// Provider factories may pass an empty string when their public constructor
/// uses an optional string with a default. An explicitly non-empty value
/// always wins; an absent environment variable is reported as a typed error.
pub fn load_api_key(
  api_key : String,
  environment_variable_name~ : String,
  api_key_parameter_name? : String = "api_key",
  description~ : String,
) -> String raise @provider.LoadAPIKeyError {
  if api_key != "" {
    return api_key
  }
  match @env.get_env_var(environment_variable_name) {
    Some(value) if value != "" => value
    Some(_) | None =>
      raise @provider.LoadAPIKeyError(
        environment_variable_name~,
        api_key_parameter_name~,
        description~,
        message="{description} API key is missing. Pass it using the '{api_key_parameter_name}' parameter or the {environment_variable_name} environment variable.",
      )
  }
}

///|
/// Load a required string setting from an explicit value or an environment
/// variable.
pub fn load_setting(
  setting_value : String,
  environment_variable_name~ : String,
  setting_name~ : String,
  description~ : String,
) -> String raise @provider.LoadSettingError {
  if setting_value != "" {
    return setting_value
  }
  match @env.get_env_var(environment_variable_name) {
    Some(value) if value != "" => value
    Some(_) | None =>
      raise @provider.LoadSettingError(
        environment_variable_name~,
        setting_name~,
        description~,
        message="{description} setting is missing. Pass it using the '{setting_name}' parameter or the {environment_variable_name} environment variable.",
      )
  }
}

///|
/// Load an optional setting. Empty explicit values and missing environment
/// variables both resolve to `None`.
pub fn load_optional_setting(
  setting_value : String,
  environment_variable_name~ : String,
) -> String? {
  if setting_value != "" {
    return Some(setting_value)
  }
  match @env.get_env_var(environment_variable_name) {
    Some(value) if value != "" => Some(value)
    _ => None
  }
}
