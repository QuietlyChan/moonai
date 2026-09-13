///|
/// The concrete Google chat model (generateContent wire protocol).
struct GoogleChatLanguageModel {
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
fn google_chat_value(
  model_id : GoogleChatModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
  id_generator~ : @provider_utils.IdGenerator,
) -> GoogleChatLanguageModel {
  {
    provider_name: "google.chat",
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
/// Build the generateContent request body.
fn GoogleChatLanguageModel::prepare(
  _self : GoogleChatLanguageModel,
  options : @provider.LanguageModelV4CallOptions,
) -> (Json, Array[@provider.Warning]) raise {
  let warnings : Array[@provider.Warning] = []
  let (contents, system_instruction) = google_convert_messages(options.prompt)
  let fields : Map[String, Json] = Map([("contents", Json::array(contents))])
  if system_instruction != "" {
    fields["systemInstruction"] = { "parts": [{ "text": system_instruction }] }
  }
  let generation_config : Map[String, Json] = Map([])
  if options.max_output_tokens is Some(value) {
    generation_config["maxOutputTokens"] = Json::number(value.to_double())
  }
  if options.temperature is Some(value) {
    generation_config["temperature"] = Json::number(value)
  }
  if options.top_p is Some(value) {
    generation_config["topP"] = Json::number(value)
  }
  if options.top_k is Some(value) {
    generation_config["topK"] = Json::number(value)
  }
  if options.stop_sequences.length() > 0 {
    generation_config["stopSequences"] = Json::array(
      [
        for value in options.stop_sequences => Json::string(value)
      ],
    )
  }
  match options.response_format {
    @provider.V4ResponseJson(format) => {
      generation_config["responseMimeType"] = Json::string("application/json")
      if format.schema is Some(schema) {
        generation_config["responseJsonSchema"] = schema
      }
    }
    _ => ()
  }
  if generation_config.length() > 0 {
    fields["generationConfig"] = Json::object(generation_config)
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
        tools.push({ "functionDeclarations": Json::object(function) })
      }
      @provider.V4ProviderTool(value) =>
        warnings.push(
          @provider.Warning::unsupported("provider-defined tool \{value.id}"),
        )
    }
  }
  if tools.length() > 0 {
    // Gemini expects one tools array whose entries carry functionDeclarations.
    let declarations : Array[Json] = []
    for entry in tools {
      if entry is { "functionDeclarations": declaration, .. } {
        declarations.push(declaration)
      }
    }
    fields["tools"] = Json::array([
      { "functionDeclarations": Json::array(declarations) },
    ])
    match options.tool_choice {
      Some(@provider.V4ToolChoiceNone) => tool_choice = Some({ "mode": "NONE" })
      Some(@provider.V4ToolChoiceRequired) =>
        tool_choice = Some({ "mode": "ANY" })
      Some(@provider.V4ToolChoiceTool(name)) =>
        tool_choice = Some({
          "mode": "ANY",
          "allowedFunctionNames": Json::array([Json::string(name)]),
        })
      _ => ()
    }
    if tool_choice is Some(value) {
      fields["toolConfig"] = value
    }
  }
  (Json::object(fields), warnings)
}

///|
/// Map a generateContent parts array onto V4 content entries.
fn google_parts_to_content(
  parts : Array[Json],
  generate_id : @provider_utils.IdGenerator,
) -> Array[@provider.LanguageModelV4Content] {
  let content : Array[@provider.LanguageModelV4Content] = []
  for part in parts {
    match part {
      { "text": String(text), .. } =>
        if text != "" {
          if part is { "thought": True, .. } {
            content.push(
              @provider.V4ReasoningOutput({ text, provider_metadata: Map([]), }),
            )
          } else {
            content.push(
              @provider.V4TextOutput({ text, provider_metadata: Map([]), }),
            )
          }
        }
      { "functionCall": { "name": String(name), .. }, .. } => {
        let args = match part {
          { "functionCall": { "args": Object(args), .. }, .. } => args
          _ => Map([])
        }
        let id = match part {
          { "functionCall": { "id": String(call_id), .. }, .. } => call_id
          _ => generate_id()
        }
        content.push(
          @provider.V4ToolCallOutput({
            tool_call_id: id,
            tool_name: name,
            input: Json::object(args).stringify(),
            provider_executed: false,
            dynamic: false,
            provider_metadata: Map([]),
          }),
        )
      }
      {
        "inlineData": {
          "mimeType": String(media_type),
          "data": String(payload),
          ..
        },
        ..
      } =>
        content.push(
          @provider.V4FileOutput({
            media_type,
            data: @provider.V4GeneratedFileBase64(payload),
            provider_metadata: Map([]),
          }),
        )
      _ => ()
    }
  }
  content
}

///|
/// Extract usageMetadata into the V4 usage contract (Gemini counts thought
/// tokens separately from candidate output).
fn google_usage(value : Json?) -> @provider.LanguageModelV4Usage {
  match value {
    Some(Object(fields)) => {
      let prompt_tokens = match fields.get("promptTokenCount") {
        Some(Number(value, ..)) => value.to_int()
        _ => 0
      }
      let candidates_tokens = match fields.get("candidatesTokenCount") {
        Some(Number(value, ..)) => value.to_int()
        _ => 0
      }
      let thoughts_tokens = match fields.get("thoughtsTokenCount") {
        Some(Number(value, ..)) => value.to_int()
        _ => 0
      }
      {
        input_tokens: {
          total: Some(prompt_tokens),
          no_cache: Some(prompt_tokens),
          cache_read: None,
          cache_write: None,
        },
        output_tokens: {
          total: Some(candidates_tokens),
          text: Some(candidates_tokens - thoughts_tokens),
          reasoning: Some(thoughts_tokens),
        },
        raw: Some(Json::object(fields)),
      }
    }
    _ => @provider.LanguageModelV4Usage::unknown()
  }
}

///|
pub impl @provider.LanguageModelV4 for GoogleChatLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for GoogleChatLanguageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.LanguageModelV4 for GoogleChatLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.LanguageModelV4 for GoogleChatLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  [
    @provider.SupportedUrlRule::http("image/*"),
    @provider.SupportedUrlRule::http("application/pdf"),
    @provider.SupportedUrlRule::http("audio/*"),
    @provider.SupportedUrlRule::http("video/*"),
  ]
}

///|
pub impl @provider.LanguageModelV4 for GoogleChatLanguageModel with fn do_generate(
  self,
  options,
) {
  let (body, warnings) = self.prepare(options)
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url="\{self.base_url}/\{get_model_path(self.model_id)}:generateContent",
    headers=@provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(
        @provider_utils.merge_headers(
          Map([
            (
              "x-goog-api-key",
              @provider_utils.load_api_key(
                self.api_key,
                environment_variable_name="GOOGLE_GENERATIVE_AI_API_KEY",
                description="Google Gemini",
              ),
            ),
            ("Content-Type", "application/json"),
          ]),
          self.headers,
        ),
        options.headers,
      ),
      ["ai-sdk/\{self.provider_name}/\{VERSION}"],
    ),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=google_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let value = response.value
  let content : Array[@provider.LanguageModelV4Content] = []
  let mut finish_raw : String? = None
  if value is Object(fields) {
    match fields.get("promptFeedback") {
      Some({ "blockReason": String(reason), .. }) => finish_raw = Some(reason)
      _ => ()
    }
    if fields.get("candidates") is Some(Array(candidates)) &&
      candidates.length() > 0 {
      match candidates[0] {
        { "finishReason": String(reason), .. } => finish_raw = Some(reason)
        _ => ()
      }
      if candidates[0] is { "content": { "parts": Array(parts), .. }, .. } {
        for part in google_parts_to_content(parts, self.id_generator) {
          content.push(part)
        }
      }
    }
  }
  {
    content,
    finish_reason: google_map_finish_reason(finish_raw),
    usage: google_usage(
      match value {
        Object(fields) => fields.get("usageMetadata")
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
      ..@provider.ResponseMetadata::empty(),
      headers: response.response.headers,
      body: Some(value.stringify()),
    }),
    warnings,
  }
}
