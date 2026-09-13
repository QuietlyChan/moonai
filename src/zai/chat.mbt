///|
/// Z.AI error payloads are either flat (`{ code, message }`) or nested under
/// an `error` key.
fn zai_error_to_message(value : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match value {
    Object(fields) => {
      let payload = match fields.get("error") {
        Some(Object(error)) => error
        _ => fields
      }
      match payload.get("message") {
        Some(String(message)) => Some(message)
        _ => None
      }
    }
    _ => None
  }
}

///|
fn zai_error_structure() -> @openai_compatible.OpenAICompatibleErrorStructure {
  @openai_compatible.OpenAICompatibleErrorStructure::new(
    error_to_message=zai_error_to_message,
  )
}

///|
/// Map the `zai` provider options onto Z.AI's snake-case wire fields and drop
/// the OpenAI settings Z.AI does not accept (`frequencyPenalty`,
/// `presencePenalty`, `seed`, `user`, `verbosity`; callers get explicit
/// unsupported warnings for the first three).
fn zai_transform_request_body(body : Json) -> Json {
  match body {
    Object(fields) => {
      let result : Map[String, Json] = Map([])
      for entry in fields.iter2() {
        let (key, value) = entry
        match key {
          "frequency_penalty"
          | "presence_penalty"
          | "seed"
          | "user"
          | "verbosity" => ()
          "doSample" => result["do_sample"] = value
          "toolStream" => result["tool_stream"] = value
          "requestId" => result["request_id"] = value
          "userId" => result["user_id"] = value
          "thinking" =>
            match value {
              Object(thinking) => {
                let mapped : Map[String, Json] = Map([])
                for field in thinking.iter2() {
                  match field.0 {
                    "clearThinking" => mapped["clear_thinking"] = field.1
                    other => mapped[other] = field.1
                  }
                }
                result["thinking"] = Json::object(mapped)
              }
              _ => result["thinking"] = value
            }
          other => result[other] = value
        }
      }
      Json::object(result)
    }
    other => other
  }
}

///|
/// Z.AI reports content filtering, context-window exhaustion, and network
/// errors under provider-specific raw reasons that the shared mapping leaves
/// as `other`.
fn zai_map_finish_reason(
  reason : @provider.LanguageModelV4FinishReason,
) -> @provider.LanguageModelV4FinishReason {
  let unified = match reason.raw {
    Some("sensitive") => @provider.V4FinishContentFilter
    Some("model_context_window_exceeded") => @provider.V4FinishLength
    Some("network_error") => @provider.V4FinishError
    _ => reason.unified
  }
  { unified, raw: reason.raw, }
}

///|
/// Restrict tool selection to what Z.AI actually honors and collect warnings
/// for the settings the body transform drops.
fn zai_prepare_call_options(
  options : @provider.LanguageModelV4CallOptions,
) -> (@provider.LanguageModelV4CallOptions, Array[@provider.Warning]) {
  let warnings : Array[@provider.Warning] = []
  if options.frequency_penalty is Some(_) {
    warnings.push(@provider.Warning::unsupported("frequencyPenalty"))
  }
  if options.presence_penalty is Some(_) {
    warnings.push(@provider.Warning::unsupported("presencePenalty"))
  }
  if options.seed is Some(_) {
    warnings.push(@provider.Warning::unsupported("seed"))
  }
  let mut tools = options.tools
  let mut tool_choice = options.tool_choice
  match options.tool_choice {
    Some(@provider.V4ToolChoiceNone) => {
      tools = []
      tool_choice = None
    }
    Some(@provider.V4ToolChoiceRequired) => {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="toolChoice required",
          details="Z.AI currently supports only automatic tool selection.",
        ),
      )
      tool_choice = None
    }
    Some(@provider.V4ToolChoiceTool(name)) => {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="toolChoice tool",
          details="Z.AI currently supports only automatic tool selection (requested \{name}).",
        ),
      )
      tool_choice = None
    }
    _ => ()
  }
  let effective = { ..options, tools, tool_choice, }
  (effective, warnings)
}

///|
/// The concrete Z.AI chat model: an OpenAI-compatible chat model with Z.AI's
/// wire transform, error structure, finish-reason mapping, and tool-choice
/// restrictions applied on top.
struct ZaiChatLanguageModel {
  base : @openai_compatible.OpenAICompatibleChatLanguageModel
}

///|
fn zai_chat_value(
  model_id : ZaiChatModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
  id_generator~ : @provider_utils.IdGenerator,
) -> ZaiChatLanguageModel {
  ZaiChatLanguageModel::{
    base: @openai_compatible.OpenAICompatibleChatLanguageModel::new(
      model_id,
      @openai_compatible.OpenAICompatibleChatConfig::new(
        provider_name="zai.chat",
        base_url~,
        api_key~,
        api_key_environment_variable="ZAI_API_KEY",
        headers~,
        supported_urls=[
          @provider.SupportedUrlRule::http("image/*"),
          @provider.SupportedUrlRule::http("video/*"),
        ],
        transform_request_body=zai_transform_request_body,
        error_structure=zai_error_structure(),
        idle_timeout_ms~,
        http_transport~,
        id_generator~,
      ),
    ),
  }
}

///|
pub impl @provider.LanguageModelV4 for ZaiChatLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for ZaiChatLanguageModel with fn provider(
  self,
) -> String {
  self.base.provider()
}

///|
pub impl @provider.LanguageModelV4 for ZaiChatLanguageModel with fn model_id(
  self,
) -> String {
  self.base.model_id()
}

///|
pub impl @provider.LanguageModelV4 for ZaiChatLanguageModel with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.base.supported_urls()
}

///|
pub impl @provider.LanguageModelV4 for ZaiChatLanguageModel with fn do_generate(
  self,
  options,
) {
  let (effective, extra_warnings) = zai_prepare_call_options(options)
  let result = (self.base as &@provider.LanguageModelV4).do_generate(effective)
  let warnings = result.warnings.copy()
  for warning in extra_warnings {
    warnings.push(warning)
  }
  {
    ..result,
    finish_reason: zai_map_finish_reason(result.finish_reason),
    warnings,
  }
}

///|
pub impl @provider.LanguageModelV4 for ZaiChatLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  let (effective, extra_warnings) = zai_prepare_call_options(options)
  let wrapped = part => {
    match part {
      @provider.V4StreamStart(warnings~) => {
        let merged = warnings.copy()
        for warning in extra_warnings {
          merged.push(warning)
        }
        on_event(@provider.V4StreamStart(warnings=merged))
      }
      @provider.V4Finish(usage~, reason~, provider_metadata~) =>
        on_event(
          @provider.V4Finish(
            usage~,
            reason=zai_map_finish_reason(reason),
            provider_metadata~,
          ),
        )
      other => on_event(other)
    }
  }
  (self.base as &@provider.LanguageModelV4).do_stream(effective, wrapped)
}
