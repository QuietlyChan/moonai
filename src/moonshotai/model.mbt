///|
/// Moonshot AI provider factory.
pub struct MoonshotAIProvider {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv id_generator : @provider_utils.IdGenerator
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Return whether a Moonshot model supports native JSON Schema output.
pub fn get_model_structured_output_support(model_id : String) -> Bool {
  model_id.has_prefix("kimi-k")
}

///|
/// AI SDK-style camel-case alias.
pub fn getModelStructuredOutputSupport(model_id : String) -> Bool {
  get_model_structured_output_support(model_id)
}

///|
fn moonshotai_error_message(json : Json) -> String? raise {
  @provider.check_cancellation(None)
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}

///|
fn moonshotai_error_structure() -> @openai_compatible.OpenAICompatibleErrorStructure {
  @openai_compatible.OpenAICompatibleErrorStructure::new(
    error_to_message=moonshotai_error_message,
  )
}

///|
fn copy_json_object(values : Map[String, Json]) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for entry in values.iter2() {
    result[entry.0] = entry.1
  }
  result
}

///|
fn strip_moonshot_schema_keyword(body : Map[String, Json]) -> Unit {
  match body.get("response_format") {
    Some(Object(response_format)) =>
      match response_format.get("json_schema") {
        Some(Object(json_schema)) =>
          match json_schema.get("schema") {
            Some(Object(schema)) => {
              let schema_copy = copy_json_object(schema)
              schema_copy.remove("$schema")
              let json_schema_copy = copy_json_object(json_schema)
              json_schema_copy["schema"] = Json::object(schema_copy)
              let response_format_copy = copy_json_object(response_format)
              response_format_copy["json_schema"] = Json::object(
                json_schema_copy,
              )
              body["response_format"] = Json::object(response_format_copy)
            }
            _ => ()
          }
        _ => ()
      }
    _ => ()
  }
}

///|
fn moonshotai_transform_request_body(json : Json) -> Json {
  guard json is Object(source) else { return json }
  let body = copy_json_object(source)
  match body.get("thinking") {
    Some(Object(value)) => {
      let thinking = copy_json_object(value)
      match thinking.get("budgetTokens") {
        Some(tokens) => {
          thinking["budget_tokens"] = tokens
          thinking.remove("budgetTokens")
        }
        None => ()
      }
      body["thinking"] = Json::object(thinking)
    }
    _ => ()
  }
  match body.get("reasoningHistory") {
    Some(value) => {
      body["reasoning_history"] = value
      body.remove("reasoningHistory")
    }
    None => ()
  }
  strip_moonshot_schema_keyword(body)
  Json::object(body)
}

///|
/// Create a Moonshot AI provider.
pub fn create_moonshot_ai(
  api_key? : String = "",
  base_url? : String = "https://api.moonshot.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> MoonshotAIProvider {
  {
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    id_generator: id_generator.unwrap_or(@provider_utils.generate_id),
    http_transport: http_transport.unwrap_or(
      @provider_utils.native_http_transport(),
    ),
  }
}

///|
/// AI SDK-style provider factory.
pub fn createMoonshotAI(
  api_key? : String = "",
  base_url? : String = "https://api.moonshot.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> MoonshotAIProvider {
  create_moonshot_ai(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  )
}

///|
fn MoonshotAIProvider::language_model_value(
  self : MoonshotAIProvider,
  model_id : MoonshotAIChatModelId,
) -> @openai_compatible.OpenAICompatibleChatLanguageModel {
  @openai_compatible.OpenAICompatibleChatLanguageModel::new(
    model_id,
    @openai_compatible.OpenAICompatibleChatConfig::new(
      provider_name="moonshotai.chat",
      base_url=self.base_url,
      api_key=self.api_key,
      api_key_environment_variable="MOONSHOT_API_KEY",
      headers=self.headers,
      include_usage=true,
      supports_structured_outputs=get_model_structured_output_support(model_id),
      transform_request_body=moonshotai_transform_request_body,
      error_structure=moonshotai_error_structure(),
      convert_usage=convert_moonshotai_chat_usage,
      idle_timeout_ms=self.idle_timeout_ms,
      id_generator=self.id_generator,
      http_transport=self.http_transport,
    ),
  )
}

///|
/// Select a Moonshot AI language model.
pub fn MoonshotAIProvider::language_model(
  self : MoonshotAIProvider,
  model_id : MoonshotAIChatModelId,
) -> &@provider.LanguageModelV4 {
  let model = self.language_model_value(model_id)
  model as &@provider.LanguageModelV4
}

///|
/// AI SDK-style language-model selector.
pub fn MoonshotAIProvider::languageModel(
  self : MoonshotAIProvider,
  model_id : MoonshotAIChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// Select a Moonshot AI chat model.
pub fn MoonshotAIProvider::chat_model(
  self : MoonshotAIProvider,
  model_id : MoonshotAIChatModelId,
) -> &@provider.LanguageModelV4 {
  self.language_model(model_id)
}

///|
/// AI SDK-style chat-model selector.
pub fn MoonshotAIProvider::chatModel(
  self : MoonshotAIProvider,
  model_id : MoonshotAIChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat_model(model_id)
}

///|
/// Short chat selector.
pub fn MoonshotAIProvider::chat(
  self : MoonshotAIProvider,
  model_id : MoonshotAIChatModelId,
) -> &@provider.LanguageModelV4 {
  self.chat_model(model_id)
}

///|
/// Construct a default Moonshot AI language model directly.
pub fn moonshotai(
  model_id : MoonshotAIChatModelId,
  api_key? : String = "",
  base_url? : String = "https://api.moonshot.ai/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  create_moonshot_ai(
    api_key~,
    base_url~,
    headers~,
    idle_timeout_ms~,
    http_transport?,
    id_generator?,
  ).language_model(model_id)
}
