///|
/// Runtime configuration shared by the runnable examples.
pub struct ExampleConfig {
  provider : String
  model : String
  api_key : String
  base_url : String?
  demo : Bool
}

///|
fn non_empty_env(name : String) -> String? {
  match @env.get_env_var(name) {
    Some(value) => {
      let trimmed = value.trim().to_owned()
      if trimmed == "" {
        None
      } else {
        Some(trimmed)
      }
    }
    None => None
  }
}

///|
fn default_model(provider : String) -> String {
  match provider {
    "openai" => "gpt-4.1-mini"
    "anthropic" => "claude-sonnet-4-5"
    "deepseek" => "deepseek-chat"
    "alibaba" => "qwen-plus"
    "minimax" => "MiniMax-M2.1"
    "openai-compatible" => "local-model"
    "open-responses" => "local-model"
    _ => "moonai-demo"
  }
}

///|
fn provider_api_key_environment(provider : String) -> String? {
  match provider {
    "openai" => Some("OPENAI_API_KEY")
    "anthropic" => Some("ANTHROPIC_API_KEY")
    "deepseek" => Some("DEEPSEEK_API_KEY")
    "alibaba" => Some("ALIBABA_API_KEY")
    "minimax" => Some("MINIMAX_API_KEY")
    _ => None
  }
}

///|
fn resolve_api_key(provider : String) -> String {
  match non_empty_env("MOONAI_API_KEY") {
    Some(value) => value
    None =>
      match provider_api_key_environment(provider) {
        Some(name) => non_empty_env(name).unwrap_or("")
        None => ""
      }
  }
}

///|
/// Load the provider used by examples from environment variables.
///
/// `MOONAI_PROVIDER` defaults to `demo`. Live providers use
/// `MOONAI_MODEL`, `MOONAI_API_KEY`, and optional `MOONAI_BASE_URL`.
pub fn load_example_config() -> ExampleConfig {
  let provider = non_empty_env("MOONAI_PROVIDER").unwrap_or("demo").to_lower()
  {
    provider,
    model: non_empty_env("MOONAI_MODEL").unwrap_or(default_model(provider)),
    api_key: resolve_api_key(provider),
    base_url: non_empty_env("MOONAI_BASE_URL"),
    demo: provider == "demo",
  }
}

///|
/// Return the display name used by the examples.
pub fn ExampleConfig::display_provider(self : ExampleConfig) -> String {
  if self.demo {
    "demo"
  } else {
    self.provider
  }
}

///|
/// Return the configured model identifier without exposing credentials.
pub fn ExampleConfig::model_id(self : ExampleConfig) -> String {
  self.model
}

///|
/// Return whether the examples are using the local deterministic model.
pub fn ExampleConfig::is_demo(self : ExampleConfig) -> Bool {
  self.demo
}

///|
fn require_base_url(config : ExampleConfig) -> String raise {
  match config.base_url {
    Some(value) => value
    None =>
      fail(
        "MOONAI_BASE_URL is required when MOONAI_PROVIDER is \"" +
        config.provider +
        "\"",
      )
  }
}

///|
/// Construct the configured provider behind the common V4 model contract.
pub fn ExampleConfig::language_model(
  self : ExampleConfig,
) -> &@provider.LanguageModelV4 raise {
  match self.provider {
    "demo" => {
      let model = DemoLanguageModel::new()
      model as &@provider.LanguageModelV4
    }
    "openai" =>
      @openai.openai(self.model, api_key=self.api_key, base_url?=self.base_url)
    "anthropic" =>
      @anthropic.anthropic(
        self.model,
        api_key=self.api_key,
        base_url?=self.base_url,
      )
    "deepseek" =>
      @deepseek.deepseek(
        self.model,
        api_key=self.api_key,
        base_url?=self.base_url,
      )
    "alibaba" =>
      @alibaba.alibaba(
        self.model,
        api_key=self.api_key,
        base_url?=self.base_url,
      )
    "minimax" =>
      @minimax.minimax(
        self.model,
        api_key=self.api_key,
        base_url?=self.base_url,
      )
    "openai-compatible" =>
      @openai_compatible.openai_compatible(
        provider_name="openai-compatible",
        base_url=require_base_url(self),
        model_id=self.model,
        api_key=self.api_key,
      )
    "open-responses" =>
      @open_responses.create_open_responses(
        provider_name="open-responses",
        url=require_base_url(self),
        api_key=self.api_key,
      ).language_model(self.model)
    value =>
      fail(
        "Unsupported MOONAI_PROVIDER \"" +
        value +
        "\". Expected demo, openai, anthropic, deepseek, alibaba, minimax, openai-compatible, or open-responses.",
      )
  }
}
