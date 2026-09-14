///|
/// Version of the Moonai harness-fx subpackage.
pub const VERSION : String = "0.1.0"

///|
/// Environment variables the fx subscription resolver may set.
pub const FX_CHATGPT_ACCESS_TOKEN_ENV : String = "AI_SDK_FX_CHATGPT_ACCESS_TOKEN"

///|
/// Account-id env var for the ChatGPT provider.
pub const FX_CHATGPT_ACCOUNT_ID_ENV : String = "AI_SDK_FX_CHATGPT_ACCOUNT_ID"

///|
/// Access-token env var for the Grok provider.
pub const FX_GROK_ACCESS_TOKEN_ENV : String = "AI_SDK_FX_GROK_ACCESS_TOKEN"

///|
/// Account-id env var for the Grok provider.
pub const FX_GROK_ACCOUNT_ID_ENV : String = "AI_SDK_FX_GROK_ACCOUNT_ID"

///|
/// A resolved fx subscription credential for one provider (chatgpt/grok).
pub(all) struct FxSubscriptionCredential {
  access_token : String
  account_id : String
} derive(Debug, Eq)

///|
/// Convert a provider name ("chatgpt"/"grok") into its access-token env var.
pub fn fx_access_token_environment_variable(provider~ : String) -> String? {
  match provider {
    "chatgpt" => Some(FX_CHATGPT_ACCESS_TOKEN_ENV)
    "grok" => Some(FX_GROK_ACCESS_TOKEN_ENV)
    _ => None
  }
}

///|
/// Convert a provider name into its account-id env var.
pub fn fx_account_id_environment_variable(provider~ : String) -> String? {
  match provider {
    "chatgpt" => Some(FX_CHATGPT_ACCOUNT_ID_ENV)
    "grok" => Some(FX_GROK_ACCOUNT_ID_ENV)
    _ => None
  }
}

///|
/// Fold resolved credentials into the environment map. Providers without a
/// credential are skipped; an empty result means nothing was resolved.
pub fn fx_merge_subscription_environment(
  environment~ : Map[String, String],
  provider~ : String,
  credential~ : FxSubscriptionCredential,
) -> Map[String, String] {
  match fx_access_token_environment_variable(provider~) {
    Some(key) => environment[key] = credential.access_token
    None => ()
  }
  match fx_account_id_environment_variable(provider~) {
    Some(key) => environment[key] = credential.account_id
    None => ()
  }
  environment
}

///|
/// Build the sandbox authentication-file grants: every fx variable present
/// in the host env is forwarded into the sandbox exactly when credential
/// brokering is unavailable (upstream brokering keeps the real values
/// host-side and passes fake ones into the sandbox).
pub fn fx_subscription_authentication_files(
  env~ : Map[String, String],
  sandbox_env~ : Map[String, String],
  credential_brokering_available~ : Bool,
) -> Array[String] {
  let variables : Array[String] = [
    FX_CHATGPT_ACCESS_TOKEN_ENV,
    FX_CHATGPT_ACCOUNT_ID_ENV,
    FX_GROK_ACCESS_TOKEN_ENV,
    FX_GROK_ACCOUNT_ID_ENV,
  ]
  let forwarded : Array[String] = []
  for variable in variables {
    match env.get(variable) {
      Some(_) if !credential_brokering_available => forwarded.push(variable)
      _ => ()
    }
  }
  for variable in forwarded {
    ignore(sandbox_env.get(variable))
  }
  forwarded
}
