///|
/// The concrete Cohere chat model (v2 wire protocol with typed stream events
/// and thinking/citations support).
struct CohereChatLanguageModel {
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
fn cohere_chat_value(
  model_id : CohereChatModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
  id_generator~ : @provider_utils.IdGenerator,
) -> CohereChatLanguageModel {
  {
    provider_name: "cohere.chat",
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
fn CohereChatLanguageModel::prepare(
  self : CohereChatLanguageModel,
  options : @provider.LanguageModelV4CallOptions,
) -> (Json, Array[@provider.Warning]) raise {
  let warnings : Array[@provider.Warning] = []
  if options.top_k is Some(_) {
    warnings.push(@provider.Warning::unsupported("topK"))
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["cohere"],
  )
  let mut thinking : Json? = None
  for entry in resolution.values.iter2() {
    if entry.0 == "thinking" {
      thinking = Some(entry.1)
    }
  }
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let documents : Array[Json] = []
  let messages = cohere_convert_messages(options.prompt, documents, warnings)
  let fields : Map[String, Json] = Map([
    ("model", Json::string(self.model_id)),
    ("messages", Json::array(messages)),
  ])
  if options.max_output_tokens is Some(value) {
    fields["max_tokens"] = Json::number(value.to_double())
  }
  if options.temperature is Some(value) {
    fields["temperature"] = Json::number(value)
  }
  if options.top_p is Some(value) {
    fields["top_p"] = Json::number(value)
  }
  if options.top_k is Some(value) {
    fields["k"] = Json::number(value)
  }
  if options.seed is Some(value) {
    fields["seed"] = Json::number(value.to_double())
  }
  if options.stop_sequences.length() > 0 {
    fields["stop_sequences"] = Json::array(
      [
        for value in options.stop_sequences => Json::string(value)
      ],
    )
  }
  match options.response_format {
    @provider.V4ResponseJson(format) => {
      let format_fields : Map[String, Json] = Map([
        ("type", Json::string("json_object")),
      ])
      if format.schema is Some(schema) {
        format_fields["json_schema"] = schema
      }
      fields["response_format"] = Json::object(format_fields)
    }
    _ => ()
  }
  let (tools, tool_choice) = cohere_prepare_tools(
    options.tools,
    options.tool_choice,
    warnings,
  )
  if tools.length() > 0 {
    fields["tools"] = Json::array(tools)
    if tool_choice is Some(value) {
      fields["tool_choice"] = Json::string(value)
    }
  }
  if documents.length() > 0 {
    fields["documents"] = Json::array(documents)
  }
  match thinking {
    Some(Object(thinking_fields)) => {
      let mapped : Map[String, Json] = Map([])
      match thinking_fields.get("type") {
        Some(String(value)) => mapped["type"] = Json::string(value)
        _ => mapped["type"] = Json::string("enabled")
      }
      if thinking_fields.get("tokenBudget") is Some(value) {
        mapped["token_budget"] = value
      }
      fields["thinking"] = Json::object(mapped)
    }
    Some(_) => ()
    None =>
      match options.reasoning {
        @provider.V4ReasoningProviderDefault => ()
        @provider.V4ReasoningNone => fields["thinking"] = { "type": "disabled" }
        _ => {
          let budget = @provider_utils.map_reasoning_to_provider_budget(
            options.reasoning.to_reasoning_effort(),
            32_768,
            32_768,
            warnings,
          )
          match budget {
            Some(value) =>
              fields["thinking"] = {
                "type": "enabled",
                "token_budget": Json::number(value.to_double()),
              }
            None => ()
          }
        }
      }
  }
  (Json::object(fields), warnings)
}

///|
pub impl @provider.LanguageModelV4 for CohereChatLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for CohereChatLanguageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.LanguageModelV4 for CohereChatLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.LanguageModelV4 for CohereChatLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  [@provider.SupportedUrlRule::http("image/*")]
}

///|
pub impl @provider.LanguageModelV4 for CohereChatLanguageModel with fn do_generate(
  self,
  options,
) {
  let (body, warnings) = self.prepare(options)
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/chat"),
    headers=cohere_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
    ),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=cohere_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let value = response.value
  let content : Array[@provider.LanguageModelV4Content] = []
  let mut finish_raw : String? = None
  let mut generation_id : String? = None
  let mut usage_json : Json? = None
  if value is Object(fields) {
    match fields.get("generation_id") {
      Some(String(id)) => generation_id = Some(id)
      _ => ()
    }
    usage_json = fields.get("usage")
    match fields.get("finish_reason") {
      Some(String(reason)) => finish_raw = Some(reason)
      _ => ()
    }
    if fields.get("message") is Some(Object(message)) {
      if message.get("content") is Some(Array(parts)) {
        for part in parts {
          match part {
            { "type": "text", "text": String(text), .. } if text != "" =>
              content.push(
                @provider.V4TextOutput({ text, provider_metadata: Map([]), }),
              )
            { "type": "thinking", "thinking": String(text), .. } if text != "" =>
              content.push(
                @provider.V4ReasoningOutput({
                  text,
                  provider_metadata: Map([]),
                }),
              )
            _ => ()
          }
        }
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
            } => {
              let input = if arguments == "null" { "{}" } else { arguments }
              content.push(
                @provider.V4ToolCallOutput({
                  tool_call_id: id,
                  tool_name: name,
                  input,
                  provider_executed: false,
                  dynamic: false,
                  provider_metadata: Map([]),
                }),
              )
            }
            _ => ()
          }
        }
      }
      if message.get("citations") is Some(Array(citations)) {
        for citation in citations {
          content.push(
            @provider.V4SourceOutput(
              @provider.V4DocumentSource(
                id=(self.id_generator)(),
                media_type="text/plain",
                title="Document",
                filename=None,
                provider_metadata=Map([("cohere", citation)]),
              ),
            ),
          )
        }
      }
    }
  }
  {
    content,
    finish_reason: cohere_map_finish_reason(finish_raw),
    usage: cohere_usage(usage_json),
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
      id: generation_id,
      headers: response.response.headers,
      body: Some(value.stringify()),
    }),
    warnings,
  }
}
