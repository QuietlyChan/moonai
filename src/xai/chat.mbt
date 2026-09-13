///|
/// The concrete xAI chat model: OpenAI-shaped wire plus reasoning_content,
/// citations, continuation skips, and grok-specific option handling.
struct XaiChatLanguageModel {
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
fn xai_chat_value(
  model_id : XaiChatModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
  id_generator~ : @provider_utils.IdGenerator,
) -> XaiChatLanguageModel {
  {
    provider_name: "xai.chat",
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
/// Build the request body and warning list for a call.
fn XaiChatLanguageModel::prepare(
  self : XaiChatLanguageModel,
  options : @provider.LanguageModelV4CallOptions,
) -> (Json, Array[@provider.Warning]) raise {
  let warnings : Array[@provider.Warning] = []
  if options.top_k is Some(_) {
    warnings.push(@provider.Warning::unsupported("topK"))
  }
  if options.frequency_penalty is Some(_) {
    warnings.push(@provider.Warning::unsupported("frequencyPenalty"))
  }
  if options.presence_penalty is Some(_) {
    warnings.push(@provider.Warning::unsupported("presencePenalty"))
  }
  if options.stop_sequences.length() > 0 {
    warnings.push(@provider.Warning::unsupported("stopSequences"))
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["xai"],
  )
  let mut logprobs : Bool = false
  let mut top_logprobs : Json? = None
  let mut service_tier : Json? = None
  let mut explicit_effort : String? = None
  let mut parallel_function_calling : Json? = None
  for entry in resolution.values.iter2() {
    match entry.0 {
      "logprobs" => logprobs = entry.1 is True
      "topLogprobs" => {
        top_logprobs = Some(entry.1)
        logprobs = true
      }
      "serviceTier" => service_tier = Some(entry.1)
      "reasoningEffort" =>
        match entry.1 {
          String(value) => explicit_effort = Some(value)
          _ => ()
        }
      "parallel_function_calling" => parallel_function_calling = Some(entry.1)
      _ => ()
    }
  }
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let conversion = @openai_compatible.default_openai_compatible_v4_prompt_converter(
    options.prompt,
    self.provider_name,
  )
  for warning in conversion.warnings {
    warnings.push(warning)
  }
  let mut reasoning_effort : String? = explicit_effort
  if reasoning_effort is None {
    match options.reasoning {
      @provider.V4ReasoningProviderDefault => ()
      @provider.V4ReasoningNone =>
        if supports_reasoning_effort(self.model_id) {
          reasoning_effort = Some("none")
        } else {
          warnings.push(
            @provider.Warning::Unsupported(
              feature="reasoning",
              details="reasoning \"none\" is not supported by this model.",
            ),
          )
        }
      _ =>
        if supports_reasoning_effort(self.model_id) {
          let effort = match options.reasoning {
            @provider.V4ReasoningMinimal => "low"
            @provider.V4ReasoningLow => "low"
            @provider.V4ReasoningMedium => "medium"
            @provider.V4ReasoningHigh => "high"
            @provider.V4ReasoningXHigh =>
              if self.model_id == "grok-4.6" {
                "xhigh"
              } else {
                "high"
              }
            _ => "high"
          }
          reasoning_effort = Some(effort)
        } else {
          warnings.push(
            @provider.Warning::Unsupported(
              feature="reasoning",
              details="reasoning is not supported by this model.",
            ),
          )
        }
    }
  }
  let fields : Map[String, Json] = Map([
    ("model", Json::string(self.model_id)),
    ("messages", Json::array(conversion.messages)),
  ])
  if logprobs {
    fields["logprobs"] = Json::boolean(true)
  }
  if top_logprobs is Some(value) {
    fields["top_logprobs"] = value
  }
  if options.max_output_tokens is Some(value) {
    fields["max_completion_tokens"] = Json::number(value.to_double())
  }
  if options.temperature is Some(value) {
    fields["temperature"] = Json::number(value)
  }
  if options.top_p is Some(value) {
    fields["top_p"] = Json::number(value)
  }
  if options.seed is Some(value) {
    fields["seed"] = Json::number(value.to_double())
  }
  if reasoning_effort is Some(value) {
    fields["reasoning_effort"] = Json::string(value)
  }
  if service_tier is Some(value) {
    fields["service_tier"] = value
  }
  if parallel_function_calling is Some(value) {
    fields["parallel_function_calling"] = value
  }
  match options.response_format {
    @provider.V4ResponseJson(format) => {
      let json_schema : Map[String, Json] = Map([
        ("name", Json::string(format.name.unwrap_or("response"))),
      ])
      if format.schema is Some(schema) {
        json_schema["schema"] = schema
      }
      fields["response_format"] = {
        "type": "json_schema",
        "json_schema": Json::object(json_schema),
      }
    }
    _ => ()
  }
  let tools : Array[Json] = []
  let mut tool_choice : Json? = None
  for tool in options.tools {
    match tool {
      @provider.V4FunctionTool(definition) => {
        let function : Map[String, Json] = Map([
          ("name", Json::string(definition.name)),
        ])
        if definition.description is Some(value) {
          function["description"] = Json::string(value)
        }
        function["parameters"] = definition.input_schema
        tools.push({ "type": "function", "function": Json::object(function) })
      }
      @provider.V4ProviderTool(value) =>
        match xai_encode_provider_tool(value) {
          Some(entry) => tools.push(entry)
          None =>
            warnings.push(
              @provider.Warning::unsupported(
                "provider-defined tool \{value.id}",
              ),
            )
        }
    }
  }
  if tools.length() > 0 {
    fields["tools"] = Json::array(tools)
    match options.tool_choice {
      Some(@provider.V4ToolChoiceAuto) => ()
      Some(@provider.V4ToolChoiceNone) =>
        tool_choice = Some(Json::string("none"))
      Some(@provider.V4ToolChoiceRequired) =>
        tool_choice = Some(Json::string("required"))
      Some(@provider.V4ToolChoiceTool(name)) =>
        tool_choice = Some({ "type": "function", "function": { "name": name } })
      None => ()
    }
    if tool_choice is Some(value) {
      fields["tool_choice"] = value
    }
  }
  (Json::object(fields), warnings)
}

///|
pub impl @provider.LanguageModelV4 for XaiChatLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for XaiChatLanguageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.LanguageModelV4 for XaiChatLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.LanguageModelV4 for XaiChatLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  [@provider.SupportedUrlRule::http("image/*")]
}

///|
pub impl @provider.LanguageModelV4 for XaiChatLanguageModel with fn do_generate(
  self,
  options,
) {
  let (body, warnings) = self.prepare(options)
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/chat/completions"),
    headers=xai_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
    ),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=xai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let value = response.value
  if value is { "error": String(message), .. } {
    raise @provider.APICallError(
      message~,
      url=@provider_utils.append_path(self.base_url, "/chat/completions"),
      request_body=body.stringify(),
      request_headers=@provider_utils.copy_headers(options.headers),
      status_code=Some(200),
      response_headers=response.response.headers,
      response_body=value.stringify(),
      is_retryable=false,
      data=None,
      cause=None,
    )
  }
  let content : Array[@provider.LanguageModelV4Content] = []
  let mut text = ""
  let mut reasoning = ""
  let mut finish_raw : String? = None
  let mut service_tier : Json? = None
  if value is Object(fields) {
    match fields.get("service_tier") {
      Some(String(tier)) => service_tier = Some(Json::string(tier))
      _ => ()
    }
    match fields.get("choices") {
      Some(Array(choices)) if choices.length() > 0 => {
        let choice = choices[0]
        if choice is { "message": Object(message), .. } {
          match message.get("content") {
            Some(String(value)) => text = value
            _ => ()
          }
          // A trailing assistant message is echoed back; skip the repeat.
          if text != "" {
            match body {
              Object(body_fields) =>
                match body_fields.get("messages") {
                  Some(Array(messages)) if messages.length() > 0 =>
                    match messages[messages.length() - 1] {
                      { "role": "assistant", "content": String(repeated), .. } if repeated ==
                        text => text = ""
                      _ => ()
                    }
                  _ => ()
                }
              _ => ()
            }
          }
          match message.get("reasoning_content") {
            Some(String(value)) => reasoning = value
            _ => ()
          }
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
                } =>
                  content.push(
                    @provider.V4ToolCallOutput({
                      tool_call_id: id,
                      tool_name: name,
                      input: arguments,
                      provider_executed: false,
                      dynamic: false,
                      provider_metadata: Map([]),
                    }),
                  )
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
  if reasoning != "" {
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
  for url in xai_citations(value) {
    content.push(
      @provider.V4SourceOutput(
        @provider.V4UrlSource(
          id=(self.id_generator)(),
          url~,
          title=None,
          provider_metadata=Map([]),
        ),
      ),
    )
  }
  let provider_metadata : Map[String, Json] = match service_tier {
    Some(tier) => Map([("xai", { "serviceTier": tier })])
    None => Map([])
  }
  {
    content,
    finish_reason: xai_map_finish_reason(finish_raw),
    usage: @provider.LanguageModelV4Usage::from_token_usage_json(
      match value {
        Object(fields) => fields.get("usage")
        _ => None
      },
    ),
    provider_metadata,
    request: Some(
      @provider.RequestMetadata::new(
        url=self.base_url,
        headers=@provider_utils.copy_headers(options.headers),
        body=body.stringify(),
      ),
    ),
    response: Some({
      ..xai_response_metadata(value),
      headers: response.response.headers,
      body: Some(value.stringify()),
    }),
    warnings,
  }
}
