///|
/// Alibaba's Chat Completions model is an OpenAI-compatible model with a
/// provider-specific wire transform for Qwen options.
pub type AlibabaChatModel = @openai_compatible.OpenAICompatibleChatModel

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
fn alibaba_transform_chat_body(body : Json) -> Json {
  alibaba_wire_value(body)
}

///|
/// Encode an Alibaba Chat Completions request without performing transport.
/// This mirrors the model's capability flags and is useful for adapters that
/// need to inspect or sign the final DashScope request body.
pub fn encode_alibaba_chat_request(
  model_id : AlibabaChatModelId,
  options : @provider.ChatCallOptions,
  stream? : Bool = false,
) -> Json raise {
  let body = @openai_compatible.encode_chat_request(
    model_id,
    options,
    preserve_reasoning=true,
    include_usage=true,
    stream~,
    provider_name="alibaba.chat",
    supports_structured_outputs=true,
    supports_top_k=true,
    supports_frequency_penalty=false,
    prompt_converter=alibaba_prompt_converter,
  )
  alibaba_transform_chat_body(body)
}

///|
/// Construct an Alibaba Qwen Chat Completions model.
pub fn alibaba_chat(
  model_id : AlibabaChatModelId,
  api_key? : String = "",
  base_url? : String = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
  headers? : Map[String, String] = Map([]),
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
  http_transport? : &@provider_utils.HttpTransport,
  id_generator? : @provider_utils.IdGenerator,
) -> AlibabaChatModel {
  @openai_compatible.openai_compatible_wire(
    provider_name="alibaba",
    base_url~,
    model_id~,
    api_key~,
    headers~,
    preserve_reasoning=true,
    include_usage~,
    supports_structured_outputs=true,
    prompt_converter=alibaba_prompt_converter,
    transform_request_body=alibaba_transform_chat_body,
    convert_usage=convert_alibaba_chat_usage,
    idle_timeout_ms~,
    supports_top_k=true,
    supports_frequency_penalty=false,
    supported_urls=[@provider.SupportedUrlRule::http("image/*")],
    http_transport?,
    api_key_environment_variable="ALIBABA_API_KEY",
    id_generator?,
    generate_reasoning_ids=true,
  )
}
