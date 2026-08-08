///|
/// Load a required API key from an explicit value or an environment variable.
///
/// Provider factories pass `None` when their public constructor did not
/// receive a setting. An explicitly supplied value, including an empty
/// string, always wins over the environment.
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
/// Load an API key using AI SDK's optional-value contract.
///
/// `Some("")` is an explicit value and therefore takes precedence over the
/// environment. `None` falls back to the configured environment variable.
pub fn loadApiKey(
  api_key : String?,
  environment_variable_name~ : String,
  api_key_parameter_name? : String = "apiKey",
  description~ : String,
) -> String raise @provider.LoadAPIKeyError {
  match api_key {
    Some(value) => value
    None =>
      match @env.get_env_var(environment_variable_name) {
        Some(value) => value
        None =>
          raise @provider.LoadAPIKeyError(
            environment_variable_name~,
            api_key_parameter_name~,
            description~,
            message="{description} API key is missing. Pass it using the '{api_key_parameter_name}' parameter or the {environment_variable_name} environment variable.",
          )
      }
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
/// Load a required setting using AI SDK's optional-value contract.
pub fn loadSetting(
  setting_value : String?,
  environment_variable_name~ : String,
  setting_name~ : String,
  description~ : String,
) -> String raise @provider.LoadSettingError {
  match setting_value {
    Some(value) => value
    None =>
      match @env.get_env_var(environment_variable_name) {
        Some(value) => value
        None =>
          raise @provider.LoadSettingError(
            environment_variable_name~,
            setting_name~,
            description~,
            message="{description} setting is missing. Pass it using the '{setting_name}' parameter or the {environment_variable_name} environment variable.",
          )
      }
  }
}

///|
/// Load an optional setting while preserving an explicitly supplied empty
/// value. This matches AI SDK's `loadOptionalSetting` contract and lets
/// callers validate empty settings instead of silently treating them as
/// omitted.
pub fn load_optional_setting(
  setting_value : String?,
  environment_variable_name~ : String,
) -> String? {
  if setting_value is Some(_) {
    return setting_value
  }
  match @env.get_env_var(environment_variable_name) {
    Some(value) => Some(value)
    None => None
  }
}

///|
/// AI SDK-style spelling for `load_optional_setting`.
pub fn loadOptionalSetting(
  setting_value : String?,
  environment_variable_name~ : String,
) -> String? {
  load_optional_setting(setting_value, environment_variable_name~)
}
