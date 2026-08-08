///|
/// Alibaba's Chat Completions model is an OpenAI-compatible model with a
/// provider-specific wire transform for Qwen options.
type AlibabaChatModel = @openai_compatible.OpenAICompatibleChatLanguageModel

///|
/// Convert provider option field names to DashScope's snake-case wire names.
fn alibaba_wire_key(key : String) -> String {
  match key {
    "enableThinking" => "enable_thinking"
    "thinkingBudget" => "thinking_budget"
    "parallelToolCalls" => "parallel_tool_calls"
    "topK" => "top_k"
    "cacheControl" => "cache_control"
    "textType" => "text_type"
    "outputType" => "output_type"
    _ => key
  }
}

///|
fn alibaba_wire_value(value : Json) -> Json {
  match value {
    Object(values) => {
      let result : Map[String, Json] = Map([])
      for entry in values.iter2() {
        let (key, nested) = entry
        result[alibaba_wire_key(key)] = alibaba_wire_value(nested)
      }
      Json::object(result)
    }
    Array(values) =>
      Json::array([ for nested in values => alibaba_wire_value(nested) ])
    _ => value
  }
}

///|
fn alibaba_chat_top_level_field(key : String) -> Bool {
  match key {
    "model"
    | "messages"
    | "stream"
    | "stream_options"
    | "max_tokens"
    | "temperature"
    | "top_p"
    | "top_k"
    | "presence_penalty"
    | "stop"
    | "seed"
    | "response_format"
    | "enable_thinking"
    | "thinking_budget"
    | "tools"
    | "tool_choice"
    | "parallel_tool_calls" => true
    _ => false
  }
}

///|
fn alibaba_response_format(value : Json) -> Json {
  match value {
    Object(format) => {
      let result : Map[String, Json] = Map([])
      for entry in format.iter2() {
        let (key, field) = entry
        if key == "json_schema" {
          match field {
            Object(schema) => {
              let normalized : Map[String, Json] = Map([])
              for schema_entry in schema.iter2() {
                if schema_entry.0 != "strict" {
                  normalized[schema_entry.0] = schema_entry.1
                }
              }
              result[key] = Json::object(normalized)
            }
            _ => result[key] = field
          }
        } else {
          result[key] = field
        }
      }
      Json::object(result)
    }
    _ => value
  }
}

///|
fn alibaba_transform_chat_body(body : Json) -> Json {
  match alibaba_wire_value(body) {
    Object(values) => {
      let result : Map[String, Json] = Map([])
      let has_tools = values.get("tools") is Some(_)
      for entry in values.iter2() {
        let (key, value) = entry
        if alibaba_chat_top_level_field(key) &&
          !(key == "parallel_tool_calls" && !has_tools) {
          result[key] = if key == "response_format" {
            alibaba_response_format(value)
          } else {
            value
          }
        }
      }
      Json::object(result)
    }
    value => value
  }
}

///|
/// Construct the concrete Alibaba chat model behind the public V4 boundary.
fn alibaba_chat_value(
  model_id : AlibabaChatModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  include_usage~ : Bool,
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
  id_generator~ : @provider_utils.IdGenerator,
) -> AlibabaChatModel {
  @openai_compatible.OpenAICompatibleChatLanguageModel::new(
    model_id,
    @openai_compatible.OpenAICompatibleChatConfig::new(
      provider_name="alibaba.chat",
      base_url~,
      api_key~,
      api_key_environment_variable="ALIBABA_API_KEY",
      headers~,
      include_usage~,
      supports_structured_outputs=true,
      supports_top_k=true,
      supports_frequency_penalty=false,
      supported_urls=[@provider.SupportedUrlRule::http("image/*")],
      transform_request_body=alibaba_transform_chat_body,
      convert_usage=convert_alibaba_chat_usage,
      validate_response=validate_alibaba_chat_response,
      validate_stream_chunk=validate_alibaba_chat_chunk,
      idle_timeout_ms~,
      id_generator~,
      generate_reasoning_ids=true,
      text_stream_id="0",
      close_text_before_reasoning=true,
      close_text_before_tool_calls=true,
      http_transport~,
      prompt_converter=alibaba_v4_prompt_converter,
      transform_options=alibaba_apply_reasoning_v4,
    ),
  )
}
