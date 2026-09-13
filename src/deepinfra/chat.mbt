///|
/// Fix incorrect token usage for Gemini/Gemma models from DeepInfra.
///
/// DeepInfra reports completion_tokens that exclude reasoning_tokens for
/// Gemini/Gemma models, which violates the OpenAI-compatible spec and would
/// produce negative text token counts. When reasoning_tokens exceed
/// completion_tokens, add them to completion_tokens (and total_tokens).
/// Returns None when the payload needs no fix.
fn deepinfra_fix_usage_raw(usage : Json) -> Json? {
  match usage {
    Object(fields) => {
      let reasoning_tokens = match fields.get("completion_tokens_details") {
        Some(Object(details)) =>
          match details.get("reasoning_tokens") {
            Some(Number(value, ..)) => Some(value)
            _ => None
          }
        _ => None
      }
      let completion_tokens = match fields.get("completion_tokens") {
        Some(Number(value, ..)) => value
        _ => 0.0
      }
      match reasoning_tokens {
        Some(reasoning) if reasoning > completion_tokens => {
          let corrected : Map[String, Json] = Map([])
          for entry in fields.iter2() {
            if entry.0 != "completion_tokens" && entry.0 != "total_tokens" {
              corrected[entry.0] = entry.1
            }
          }
          corrected["completion_tokens"] = Json::number(
            completion_tokens + reasoning,
          )
          if fields.get("total_tokens") is Some(Number(total, ..)) {
            corrected["total_tokens"] = Json::number(total + reasoning)
          }
          Some(Json::object(corrected))
        }
        _ => None
      }
    }
    _ => None
  }
}

///|
/// The concrete DeepInfra chat model: the OpenAI-compatible chat model plus
/// the Gemini/Gemma usage fixup applied to generate results and finish
/// events.
struct DeepInfraChatLanguageModel {
  base : @openai_compatible.OpenAICompatibleChatLanguageModel
}

///|
fn deepinfra_chat_value(
  model_id : DeepInfraChatModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
  id_generator~ : @provider_utils.IdGenerator,
) -> DeepInfraChatLanguageModel {
  DeepInfraChatLanguageModel::{
    base: @openai_compatible.OpenAICompatibleChatLanguageModel::new(
      model_id,
      @openai_compatible.OpenAICompatibleChatConfig::new(
        provider_name="deepinfra.chat",
        base_url~,
        api_key~,
        api_key_environment_variable="DEEPINFRA_API_KEY",
        headers~,
        supports_structured_outputs=true,
        idle_timeout_ms~,
        http_transport~,
        id_generator~,
      ),
    ),
  }
}

///|
fn deepinfra_fixed_usage(raw : Json) -> @provider.LanguageModelV4Usage? {
  match deepinfra_fix_usage_raw(raw) {
    Some(fixed) =>
      Some(@provider.LanguageModelV4Usage::from_token_usage_json(Some(fixed)))
    None => None
  }
}

///|
pub impl @provider.LanguageModelV4 for DeepInfraChatLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for DeepInfraChatLanguageModel with fn provider(
  self,
) -> String {
  self.base.provider()
}

///|
pub impl @provider.LanguageModelV4 for DeepInfraChatLanguageModel with fn model_id(
  self,
) -> String {
  self.base.model_id()
}

///|
pub impl @provider.LanguageModelV4 for DeepInfraChatLanguageModel with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.base.supported_urls()
}

///|
pub impl @provider.LanguageModelV4 for DeepInfraChatLanguageModel with fn do_generate(
  self,
  options,
) {
  let result = (self.base as &@provider.LanguageModelV4).do_generate(options)
  match result.usage.raw {
    Some(raw) =>
      match deepinfra_fixed_usage(raw) {
        Some(fixed) => { ..result, usage: fixed, }
        None => result
      }
    None => result
  }
}

///|
pub impl @provider.LanguageModelV4 for DeepInfraChatLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  let wrapped = part => {
    match part {
      @provider.V4Finish(usage~, reason~, provider_metadata~) =>
        match usage.raw {
          Some(raw) =>
            match deepinfra_fixed_usage(raw) {
              Some(fixed) =>
                on_event(
                  @provider.V4Finish(usage=fixed, reason~, provider_metadata~),
                )
              None => on_event(part)
            }
          None => on_event(part)
        }
      other => on_event(other)
    }
  }
  (self.base as &@provider.LanguageModelV4).do_stream(options, wrapped)
}
