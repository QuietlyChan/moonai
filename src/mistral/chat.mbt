///|
/// The concrete Mistral chat model: OpenAI-shaped wire with thinking content
/// blocks, safe prompts, reasoning-effort whitelist, and Mistral's structured
/// output format.
struct MistralChatLanguageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  id_generator : @provider_utils.IdGenerator
  http_transport : &@provider_utils.HttpTransport
}

///|
fn mistral_chat_value(
  model_id : MistralChatModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
  id_generator~ : @provider_utils.IdGenerator,
) -> MistralChatLanguageModel {
  {
    provider_name: "mistral.chat",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    id_generator,
    http_transport,
  }
}

///|
fn MistralChatLanguageModel::mistral_request_headers(
  self : MistralChatLanguageModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="MISTRAL_API_KEY",
    description="Mistral",
  )
  let base : Map[String, String] = Map([
    ("Content-Type", "application/json"),
    ("Authorization", "Bearer \{api_key}"),
  ])
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(base, self.headers),
      extra,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
}

///|
/// Build the request body and warning list for a call.
fn MistralChatLanguageModel::prepare(
  self : MistralChatLanguageModel,
  options : @provider.LanguageModelV4CallOptions,
) -> (Json, Array[@provider.Warning]) raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  let warnings : Array[@provider.Warning] = []
  if options.top_k is Some(_) {
    warnings.push(@provider.Warning::unsupported("topK"))
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["mistral"],
  )
  let mut safe_prompt : Json? = None
  let mut reasoning_effort : String? = None
  let mut structured_outputs = true
  let mut strict_json_schema = false
  let mut document_image_limit : Json? = None
  let mut document_page_limit : Json? = None
  let mut prompt_cache_key : Json? = None
  let mut parallel_tool_calls : Json? = None
  for entry in resolution.values.iter2() {
    match entry.0 {
      "safePrompt" => safe_prompt = Some(entry.1)
      "reasoningEffort" =>
        match entry.1 {
          String(value) => reasoning_effort = Some(value)
          _ => ()
        }
      "structuredOutputs" => structured_outputs = entry.1 is True
      "strictJsonSchema" => strict_json_schema = entry.1 is True
      "documentImageLimit" => document_image_limit = Some(entry.1)
      "documentPageLimit" => document_page_limit = Some(entry.1)
      "promptCacheKey" => prompt_cache_key = Some(entry.1)
      "parallelToolCalls" => parallel_tool_calls = Some(entry.1)
      _ => ()
    }
  }
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let supports_reasoning_effort = mistral_supports_reasoning_effort(
    self.model_id,
  )
  let mut resolved_effort : String? = None
  if supports_reasoning_effort {
    match reasoning_effort {
      Some(value) => resolved_effort = Some(value)
      None =>
        match options.reasoning {
          @provider.V4ReasoningProviderDefault => ()
          @provider.V4ReasoningNone => resolved_effort = Some("none")
          _ => {
            warnings.push(
              @provider.Warning::Compatibility(
                feature="reasoning",
                details="Mistral reasoning models only support high effort.",
              ),
            )
            resolved_effort = Some("high")
          }
        }
    }
  } else {
    match options.reasoning {
      @provider.V4ReasoningProviderDefault => ()
      _ =>
        warnings.push(
          @provider.Warning::Unsupported(
            feature="reasoning",
            details="This model does not support reasoning configuration.",
          ),
        )
    }
  }
  let fields : Map[String, Json] = Map([
    ("model", Json::string(self.model_id)),
    ("messages", Json::array(mistral_convert_messages(options.prompt))),
  ])
  if safe_prompt is Some(value) {
    fields["safe_prompt"] = value
  }
  if options.max_output_tokens is Some(value) {
    fields["max_tokens"] = Json::number(value.to_double())
  }
  if options.temperature is Some(value) {
    fields["temperature"] = Json::number(value)
  }
  if options.top_p is Some(value) {
    fields["top_p"] = Json::number(value)
  }
  if options.frequency_penalty is Some(value) {
    fields["frequency_penalty"] = Json::number(value)
  }
  if options.presence_penalty is Some(value) {
    fields["presence_penalty"] = Json::number(value)
  }
  if options.stop_sequences.length() > 0 {
    fields["stop"] = Json::array(
      [
        for value in options.stop_sequences => Json::string(value)
      ],
    )
  }
  if options.seed is Some(value) {
    fields["random_seed"] = Json::number(value.to_double())
  }
  if resolved_effort is Some(value) {
    fields["reasoning_effort"] = Json::string(value)
  }
  match options.response_format {
    @provider.V4ResponseJson(format) =>
      if format.schema is Some(schema) && structured_outputs {
        let json_schema : Map[String, Json] = Map([
          ("schema", schema),
          ("strict", Json::boolean(strict_json_schema)),
          ("name", Json::string(format.name.unwrap_or("response"))),
        ])
        if format.description is Some(value) {
          json_schema["description"] = Json::string(value)
        }
        fields["response_format"] = {
          "type": "json_schema",
          "json_schema": Json::object(json_schema),
        }
      } else {
        fields["response_format"] = { "type": "json_object" }
      }
    _ => ()
  }
  if document_image_limit is Some(value) {
    fields["document_image_limit"] = value
  }
  if document_page_limit is Some(value) {
    fields["document_page_limit"] = value
  }
  if prompt_cache_key is Some(value) {
    fields["prompt_cache_key"] = value
  }
  let (tools, tool_choice) = mistral_prepare_tools(
    options.tools,
    options.tool_choice,
    warnings,
  )
  if tools.length() > 0 {
    fields["tools"] = Json::array(tools)
    if tool_choice is Some(value) {
      fields["tool_choice"] = value
    }
    if parallel_tool_calls is Some(value) {
      fields["parallel_tool_calls"] = value
    }
  }
  (Json::object(fields), warnings)
}

///|
/// Map a Mistral message content value (string or part array) onto a text
/// value plus ordered thinking blocks.
fn mistral_extract_content(content : Json, thinking : Array[String]) -> String {
  match content {
    String(text) => text
    Array(parts) => {
      let mut text = ""
      for part in parts {
        match part {
          { "type": "thinking", .. } =>
            if part is { "thinking": thinking_value, .. } {
              match mistral_thinking_text(thinking_value) {
                Some(value) if value != "" => thinking.push(value)
                _ => ()
              }
            }
          { "type": "text", "text": String(value), .. } => text = value
          _ => ()
        }
      }
      text
    }
    _ => ""
  }
}

///|
/// Flatten Mistral thinking payloads (string or text-part array).
fn mistral_thinking_text(value : Json) -> String? {
  match value {
    String(text) => Some(text)
    Array(parts) => {
      let builder = StringBuilder()
      for part in parts {
        match part {
          { "type": "text", "text": String(text), .. } =>
            builder.write_string(text)
          _ => ()
        }
      }
      Some(builder.to_string())
    }
    _ => None
  }
}

///|
pub impl @provider.LanguageModelV4 for MistralChatLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for MistralChatLanguageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.LanguageModelV4 for MistralChatLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.LanguageModelV4 for MistralChatLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  [@provider.SupportedUrlRule::http("application/pdf")]
}

///|
pub impl @provider.LanguageModelV4 for MistralChatLanguageModel with fn do_generate(
  self,
  options,
) {
  let (body, warnings) = self.prepare(options)
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/chat/completions"),
    headers=self.mistral_request_headers(extra=options.headers),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=mistral_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let value = response.value
  let mut text = ""
  let thinking : Array[String] = []
  let tool_calls : Array[@provider.LanguageModelV4ToolCall] = []
  let mut finish_raw : String? = None
  if value is Object(fields) {
    match fields.get("choices") {
      Some(Array(choices)) if choices.length() > 0 => {
        let choice = choices[0]
        if choice is { "message": Object(message), .. } {
          text = mistral_extract_content(
            message.get("content").unwrap_or(Json::null()),
            thinking,
          )
          if message.get("tool_calls") is Some(Array(calls)) {
            for call in calls {
              match call {
                {
                  "id": String(id),
                  "function": {
                    "name": String(name),
                    "arguments": String(arguments),
                    ..
                  },
                  ..
                } => {
                  let input = @json.parse(arguments) catch {
                    _ => Json::string(arguments)
                  }
                  tool_calls.push({
                    tool_call_id: id,
                    tool_name: name,
                    input: input.stringify(),
                    provider_executed: false,
                    dynamic: false,
                    provider_metadata: Map([]),
                  })
                }
                _ => ()
              }
            }
          }
        }
        if choice is { "finish_reason": String(reason), .. } {
          finish_raw = Some(reason)
        }
      }
      _ => ()
    }
  }
  let content : Array[@provider.LanguageModelV4Content] = []
  for reasoning in thinking {
    content.push(
      @provider.V4ReasoningOutput({
        text: reasoning,
        provider_metadata: Map([]),
      }),
    )
  }
  if text != "" {
    content.push(@provider.V4TextOutput({ text, provider_metadata: Map([]), }))
  }
  for call in tool_calls {
    content.push(@provider.V4ToolCallOutput(call))
  }
  {
    content,
    finish_reason: mistral_map_finish_reason(finish_raw),
    usage: @provider.LanguageModelV4Usage::from_token_usage_json(
      match value {
        Object(fields) => fields.get("usage")
        _ => None
      },
    ),
    provider_metadata: Map([]),
    request: Some(
      @provider.RequestMetadata::new(
        url=self.base_url,
        headers=@provider_utils.copy_headers(options.headers),
        body=body.stringify(),
      ),
    ),
    response: Some({
      ..mistral_response_metadata(value),
      headers: response.response.headers,
      body: Some(value.stringify()),
    }),
    warnings,
  }
}
