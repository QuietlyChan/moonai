///|
/// Cerebras error payloads carry a flat `message` field.
fn cerebras_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn cerebras_error_structure() -> @openai_compatible.OpenAICompatibleErrorStructure {
  @openai_compatible.OpenAICompatibleErrorStructure::new(
    error_to_message=cerebras_error_to_message,
  )
}

///|
/// Cerebras expects assistant reasoning history in the `reasoning` field,
/// while the shared OpenAI-compatible converter serializes it as
/// `reasoning_content`.
fn cerebras_transform_assistant_message(message : Json) -> Json {
  match message {
    Object(fields) =>
      match (fields.get("role"), fields.get("reasoning_content")) {
        (Some(String("assistant")), Some(reasoning)) => {
          let result : Map[String, Json] = Map([])
          for entry in fields.iter2() {
            if entry.0 != "reasoning_content" {
              result[entry.0] = entry.1
            }
          }
          if result.get("reasoning") is None {
            result["reasoning"] = reasoning
          }
          Json::object(result)
        }
        _ => message
      }
    other => other
  }
}

///|
fn cerebras_transform_messages(value : Json) -> Json {
  match value {
    Array(messages) =>
      Json::array(
        [
          for message in messages => {
            cerebras_transform_assistant_message(message)
          }
        ],
      )
    other => other
  }
}

///|
/// Rename the OpenAI settings Cerebras spells differently. The remaining
/// `cerebras` namespace options pass through and only need snake-case wire
/// names.
fn cerebras_transform_request_body(body : Json) -> Json {
  match body {
    Object(fields) => {
      let result : Map[String, Json] = Map([])
      for entry in fields.iter2() {
        let (key, value) = entry
        match key {
          "max_tokens" => result["max_completion_tokens"] = value
          "parallelToolCalls" => result["parallel_tool_calls"] = value
          "topLogprobs" => result["top_logprobs"] = value
          "logitBias" => result["logit_bias"] = value
          "serviceTier" => result["service_tier"] = value
          "reasoningFormat" => result["reasoning_format"] = value
          "promptCacheKey" => result["prompt_cache_key"] = value
          "messages" => result["messages"] = cerebras_transform_messages(value)
          other => result[other] = value
        }
      }
      Json::object(result)
    }
    other => other
  }
}

///|
/// Construct the concrete Cerebras chat model behind the public V4 boundary.
fn cerebras_chat_value(
  model_id : CerebrasChatModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
  id_generator~ : @provider_utils.IdGenerator,
) -> &@provider.LanguageModelV4 {
  let model = @openai_compatible.OpenAICompatibleChatLanguageModel::new(
    model_id,
    @openai_compatible.OpenAICompatibleChatConfig::new(
      provider_name="cerebras.chat",
      base_url~,
      api_key~,
      api_key_environment_variable="CEREBRAS_API_KEY",
      headers~,
      supports_structured_outputs=true,
      transform_request_body=cerebras_transform_request_body,
      error_structure=cerebras_error_structure(),
      idle_timeout_ms~,
      http_transport~,
      id_generator~,
    ),
  )
  model as &@provider.LanguageModelV4
}
