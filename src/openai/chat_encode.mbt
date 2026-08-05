///|
fn openai_prompt_option(options : Map[String, Json], field : String) -> Json? {
  match options.get("openai") {
    Some(Object(values)) =>
      match values.get(field) {
        Some(Null) | None => None
        Some(value) => Some(value)
      }
    _ => None
  }
}

///|
fn openai_prompt_cache_breakpoint(options : Map[String, Json]) -> Json? {
  openai_prompt_option(options, "promptCacheBreakpoint")
}

///|
fn openai_image_detail(options : Map[String, Json]) -> String? {
  match openai_prompt_option(options, "imageDetail") {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn with_openai_prompt_cache_breakpoint(
  content : Json,
  options : Map[String, Json],
) -> Json {
  guard content is Object(fields) else { return content }
  guard openai_prompt_cache_breakpoint(options) is Some(breakpoint) else {
    return content
  }
  let result = @provider.copy_provider_metadata(fields)
  result["prompt_cache_breakpoint"] = breakpoint
  Json::object(result)
}

///|
fn openai_image_url_value(url : String, options : Map[String, Json]) -> Json {
  let fields : Map[String, Json] = Map([("url", Json::string(url))])
  if openai_image_detail(options) is Some(detail) {
    fields["detail"] = Json::string(detail)
  }
  Json::object(fields)
}

///|
fn openai_chat_content_part(
  part : @provider.LanguageModelContentPart,
  index : Int,
) -> Json raise {
  let provider_options = part.provider_options()
  let content : Json = match part.without_provider_options() {
    @provider.Text(value) => { "type": "text", "text": value }
    @provider.ImageUrl(url) =>
      {
        "type": "image_url",
        "image_url": openai_image_url_value(url, provider_options),
      }
    @provider.ImageData(data~, media_type~) => {
      let url = openai_data_uri(
        @provider_utils.resolve_full_media_type(media_type, data),
        data,
      )
      {
        "type": "image_url",
        "image_url": openai_image_url_value(url, provider_options),
      }
    }
    @provider.AudioData(data~, format~) =>
      {
        "type": "input_audio",
        "input_audio": { "data": data, "format": format },
      }
    @provider.FileUrl(url~, media_type~, filename=_) => {
      let top_level = @provider_utils.get_top_level_media_type(media_type)
      if top_level == "image" {
        {
          "type": "image_url",
          "image_url": openai_image_url_value(url, provider_options),
        }
      } else if top_level == "audio" {
        fail("OpenAI Chat does not accept audio file URLs")
      } else if media_type == "application/pdf" {
        fail("OpenAI Chat does not accept PDF file URLs")
      } else {
        fail(
          "OpenAI Chat does not accept URL-backed file media type \{media_type}",
        )
      }
    }
    @provider.FileData(data~, media_type~, filename~) => {
      let top_level = @provider_utils.get_top_level_media_type(media_type)
      let full_media_type = @provider_utils.resolve_full_media_type(
        media_type, data,
      )
      if top_level == "image" {
        {
          "type": "image_url",
          "image_url": openai_image_url_value(
            openai_data_uri(full_media_type, data),
            provider_options,
          ),
        }
      } else if top_level == "audio" {
        let format = match full_media_type {
          "audio/wav" => "wav"
          "audio/mp3" | "audio/mpeg" => "mp3"
          _ =>
            fail(
              "OpenAI Chat does not accept audio media type \{full_media_type}",
            )
        }
        {
          "type": "input_audio",
          "input_audio": { "data": data, "format": format },
        }
      } else {
        guard full_media_type == "application/pdf" else {
          fail("OpenAI Chat does not accept file media type \{full_media_type}")
        }
        {
          "type": "file",
          "file": {
            "filename": if filename == "" {
              "part-\{index}.pdf"
            } else {
              filename
            },
            "file_data": openai_data_uri(full_media_type, data),
          },
        }
      }
    }
    @provider.FileReference(reference~, ..) =>
      {
        "type": "file",
        "file": {
          "file_id": @provider_utils.resolve_provider_reference(
            reference, "openai",
          ),
        },
      }
    @provider.Reasoning(_)
    | @provider.ReasoningFileUrl(..)
    | @provider.ReasoningFileData(..)
    | @provider.Custom(..)
    | @provider.ToolCallPart(_)
    | @provider.ToolResultPart(_)
    | @provider.ToolApprovalRequestPart(_)
    | @provider.ToolApprovalResponsePart(_) =>
      fail("OpenAI Chat does not accept this content part")
    @provider.ProviderOptions(part~, ..) =>
      openai_chat_content_part(part, index)
  }
  with_openai_prompt_cache_breakpoint(content, provider_options)
}

///|
fn openai_text_content_with_breakpoint(
  text : String,
  options : Map[String, Json],
) -> Json {
  with_openai_prompt_cache_breakpoint(
    ({ "type": "text", "text": text } : Json),
    options,
  )
}

///|
fn openai_assistant_content(
  message : @provider.LanguageModelMessage,
) -> Json raise {
  let tool_calls = message.effective_tool_calls()
  guard message.parts.length() > 0 else {
    return if tool_calls.length() > 0 && message.content == "" {
      Json::null()
    } else {
      Json::string(message.content)
    }
  }
  let text = StringBuilder::new()
  let text_parts : Array[Json] = []
  let mut has_breakpoint = false
  for part in message.parts {
    match part.without_provider_options() {
      @provider.Text(value) => {
        text.write_string(value)
        let options = part.provider_options()
        if openai_prompt_cache_breakpoint(options) is Some(_) {
          has_breakpoint = true
        }
        text_parts.push(openai_text_content_with_breakpoint(value, options))
      }
      @provider.ToolCallPart(_) => ()
      _ =>
        fail("OpenAI Chat assistant messages support text content parts only")
    }
  }
  if has_breakpoint {
    Json::array(text_parts)
  } else {
    let value = text.to_string()
    if tool_calls.length() > 0 && value == "" {
      Json::null()
    } else {
      Json::string(value)
    }
  }
}

///|
fn openai_chat_tool_call(call : @provider.ToolCall) -> Json {
  {
    "id": call.id,
    "type": "function",
    "function": { "name": call.name, "arguments": call.arguments },
  }
}

///|
/// Serialize a structured tool result using Chat Completions' string output
/// contract. A content output is serialized as JSON because Chat Completions
/// does not define a separate multimodal tool-result union.
fn openai_chat_tool_result_text(
  output : @provider.LanguageModelToolResultOutput,
) -> String {
  match output {
    @provider.LanguageModelToolTextOutput(value~, ..)
    | @provider.LanguageModelToolErrorText(value~, ..) => value
    @provider.LanguageModelToolExecutionDenied(reason~, ..) =>
      reason.unwrap_or("Tool call execution denied.")
    @provider.LanguageModelToolJsonOutput(value~, ..)
    | @provider.LanguageModelToolErrorJson(value~, ..) => value.stringify()
    @provider.LanguageModelToolContent(..) => output.to_json().stringify()
  }
}

///|
/// Read a Chat prompt-cache breakpoint from tool-result options.
fn openai_chat_tool_result_content(
  result : @provider.LanguageModelToolResult,
) -> Json {
  let value = openai_chat_tool_result_text(result.output)
  match openai_prompt_cache_breakpoint(result.provider_options) {
    Some(_) =>
      Json::array([
        with_openai_prompt_cache_breakpoint(
          ({ "type": "text", "text": value } : Json),
          result.provider_options,
        ),
      ])
    None => Json::string(value)
  }
}

///|
/// Build one Chat Completions tool message from a structured result.
fn openai_chat_tool_result_message(
  result : @provider.LanguageModelToolResult,
) -> Json {
  {
    "role": "tool",
    "tool_call_id": result.tool_call_id,
    "content": openai_chat_tool_result_content(result),
  }
}

///|
/// Return all tool messages represented by one normalized tool message. The
/// high-level prompt permits several result parts in one message, while the
/// Chat Completions wire format requires one `tool_call_id` per message.
fn openai_chat_tool_messages(
  message : @provider.LanguageModelMessage,
) -> Array[Json] {
  let result : Array[Json] = []
  for part in message.parts {
    match part.without_provider_options() {
      @provider.ToolResultPart(value) =>
        result.push(openai_chat_tool_result_message(value))
      @provider.ToolApprovalResponsePart(_) => ()
      _ => ()
    }
  }
  result
}

///|
fn openai_chat_message(
  message : @provider.LanguageModelMessage,
  system_message_mode : String,
  preserve_reasoning : Bool,
  warnings : Array[@provider.Warning],
) -> Json? raise {
  let role = match message.role {
    @provider.System =>
      if system_message_mode == "remove" {
        warnings.push(
          @provider.Warning::Other(
            message="system messages are removed for this model",
          ),
        )
        return None
      } else {
        system_message_mode
      }
    @provider.User => "user"
    @provider.Assistant => "assistant"
    @provider.Tool(_) => "tool"
  }
  let content = match message.role {
    @provider.System =>
      match openai_prompt_cache_breakpoint(message.provider_options) {
        Some(_) =>
          Json::array([
            openai_text_content_with_breakpoint(
              message.content,
              message.provider_options,
            ),
          ])
        None => Json::string(message.content)
      }
    @provider.User if message.parts.length() == 1 =>
      match message.parts[0].without_provider_options() {
        @provider.Text(value) if openai_prompt_cache_breakpoint(
            message.parts[0].provider_options(),
          )
          is None => Json::string(value)
        _ => Json::array([openai_chat_content_part(message.parts[0], 0)])
      }
    @provider.User if message.parts.length() > 0 =>
      Json::array(
        [
          for index, part in message.parts => {
            openai_chat_content_part(part, index)
          }
        ],
      )
    @provider.Assistant => openai_assistant_content(message)
    _ if message.parts.length() > 0 =>
      Json::array(
        [
          for index, part in message.parts => {
            openai_chat_content_part(part, index)
          }
        ],
      )
    _ => Json::string(message.content)
  }
  let tool_calls = message.effective_tool_calls()
  Some(
    Json::object(
      Map(
        [
          ("role", Json::string(role)),
          ("content", content),
          ..if message.role is @provider.Tool(tool_call_id) {
            [("tool_call_id", Json::string(tool_call_id))]
          },
          ..if tool_calls.length() > 0 {
            [
              (
                "tool_calls",
                Json::array(
                  [
                    for call in tool_calls => openai_chat_tool_call(call)
                  ],
                ),
              ),
            ]
          },
          ..if preserve_reasoning &&
            message.role is @provider.Assistant &&
            message.reasoning_content is Some(value) {
            [("reasoning_content", Json::string(value))]
          },
        ],
      ),
    ),
  )
}

///|
fn openai_chat_tool(tool : @provider.ToolDefinition) -> Json? {
  match tool {
    @provider.FunctionTool(name~, description~, input_schema~, strict~, ..) =>
      Some(
        Json::object(
          Map([
            ("type", Json::string("function")),
            (
              "function",
              Json::object(
                Map(
                  [
                    ("name", Json::string(name)),
                    ..if description is Some(value) {
                      [("description", Json::string(value))]
                    },
                    ("parameters", input_schema),
                    ..if strict is Some(value) {
                      [("strict", Json::boolean(value))]
                    },
                  ],
                ),
              ),
            ),
          ]),
        ),
      )
    @provider.ProviderTool(..) => None
  }
}

///|
fn openai_chat_tool_choice(choice : @provider.ToolChoice) -> Json {
  match choice {
    @provider.Auto => Json::string("auto")
    @provider.NoTool => Json::string("none")
    @provider.Required => Json::string("required")
    @provider.Named(name) =>
      { "type": "function", "function": { "name": name } }
  }
}

///|
fn openai_chat_response_format(
  format : @provider.ResponseFormat,
  strict_json_schema : Bool,
) -> Json? {
  match format {
    @provider.Text => None
    @provider.JsonResponse(config) =>
      match config.schema {
        None => Some(({ "type": "json_object" } : Json))
        Some(schema) => {
          let json_schema : Map[String, Json] = Map([
            ("name", Json::string(config.name.unwrap_or("response"))),
            ("schema", schema),
            ("strict", Json::boolean(strict_json_schema)),
          ])
          if config.description is Some(value) {
            json_schema["description"] = Json::string(value)
          }
          Some(
            (
              {
                "type": "json_schema",
                "json_schema": Json::object(json_schema),
              } : Json),
          )
        }
      }
  }
}

///|
fn prepare_openai_chat_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  provider_name : String,
  stream : Bool,
  preserve_reasoning : Bool,
  include_usage : Bool,
) -> OpenAIPreparedChatRequest raise {
  let parsed = parse_openai_chat_options(options, provider_name)
  let provider_options = parsed.options
  let warnings = parsed.warnings.copy()
  if options.top_k is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="topK",
        details="OpenAI Chat Completions does not support topK.",
      ),
    )
  }
  let capabilities = get_openai_language_model_capabilities(model_id)
  let is_reasoning_model = provider_options.force_reasoning.unwrap_or(
    capabilities.is_reasoning_model,
  )
  let reasoning_effort = match provider_options.reasoning_effort {
    Some(value) => Some(value)
    None => openai_reasoning_effort(options.reasoning_effort)
  }
  let system_message_mode = provider_options.system_message_mode.unwrap_or(
    if is_reasoning_model {
      "developer"
    } else {
      capabilities.system_message_mode
    },
  )
  let messages : Array[Json] = []
  for message in options.messages {
    if message.role is @provider.Tool(_) && message.parts.length() > 0 {
      let tool_messages = openai_chat_tool_messages(message)
      if tool_messages.length() > 0 {
        for tool_message in tool_messages {
          messages.push(tool_message)
        }
        continue
      }
    }
    if openai_chat_message(
        message, system_message_mode, preserve_reasoning, warnings,
      )
      is Some(value) {
      messages.push(value)
    }
  }
  let tools : Array[Json] = []
  for tool in options.tools {
    match openai_chat_tool(tool) {
      Some(value) => tools.push(value)
      None =>
        warnings.push(
          @provider.Warning::Unsupported(
            feature="provider tool \{tool.name()}",
            details="Provider-defined tools require the OpenAI Responses API.",
          ),
        )
    }
  }
  let mut max_tokens = options.max_output_tokens
  let mut max_completion_tokens = provider_options.max_completion_tokens
  let mut temperature = options.temperature
  let mut top_p = options.top_p
  let mut frequency_penalty = options.frequency_penalty
  let mut presence_penalty = options.presence_penalty
  let mut logit_bias = provider_options.logit_bias
  let mut logprobs = provider_options.logprobs
  let mut top_logprobs = provider_options.top_logprobs
  if is_reasoning_model {
    let allows_sampling = reasoning_effort == Some("none") &&
      capabilities.supports_non_reasoning_parameters
    if !allows_sampling {
      if temperature is Some(_) {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="temperature",
            details="temperature is not supported for reasoning models.",
          ),
        )
        temperature = None
      }
      if top_p is Some(_) {
        warnings.push(
          @provider.Warning::Unsupported(
            feature="topP",
            details="topP is not supported for reasoning models.",
          ),
        )
        top_p = None
      }
      if logprobs {
        warnings.push(
          @provider.Warning::Other(
            message="logprobs is not supported for reasoning models",
          ),
        )
        logprobs = false
        top_logprobs = None
      }
    }
    if frequency_penalty is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="frequencyPenalty",
          details="frequencyPenalty is not supported for reasoning models.",
        ),
      )
      frequency_penalty = None
    }
    if presence_penalty is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="presencePenalty",
          details="presencePenalty is not supported for reasoning models.",
        ),
      )
      presence_penalty = None
    }
    if logit_bias is Some(_) {
      warnings.push(
        @provider.Warning::Other(
          message="logitBias is not supported for reasoning models",
        ),
      )
      logit_bias = None
    }
    if max_tokens is Some(value) {
      if max_completion_tokens is None {
        max_completion_tokens = Some(value)
      }
      max_tokens = None
    }
  } else if model_id.has_prefix("gpt-4o-search-preview") ||
    model_id.has_prefix("gpt-4o-mini-search-preview") {
    if temperature is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="temperature",
          details="temperature is not supported for search preview models.",
        ),
      )
      temperature = None
    }
  }
  let mut service_tier = provider_options.service_tier
  if service_tier == Some("flex") && !capabilities.supports_flex_processing {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="serviceTier",
        details="flex processing is not supported by this model.",
      ),
    )
    service_tier = None
  }
  if service_tier == Some("priority") &&
    !capabilities.supports_priority_processing {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="serviceTier",
        details="priority processing is not supported by this model.",
      ),
    )
    service_tier = None
  }
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ("messages", Json::array(messages)),
      ..if stream {
        [
          ("stream", Json::boolean(true)),
          ..if include_usage {
            [("stream_options", ({ "include_usage": true } : Json))]
          },
        ]
      },
      ..if logit_bias is Some(value) {
        [("logit_bias", value)]
      },
      ..if logprobs {
        [("logprobs", Json::boolean(true))]
      },
      ..if top_logprobs is Some(value) {
        [("top_logprobs", Json::number(value.to_double()))]
      },
      ..if provider_options.user is Some(value) {
        [("user", Json::string(value))]
      },
      ..if provider_options.parallel_tool_calls is Some(value) {
        [("parallel_tool_calls", Json::boolean(value))]
      },
      ..if max_tokens is Some(value) {
        [("max_tokens", Json::number(value.to_double()))]
      },
      ..if max_completion_tokens is Some(value) {
        [("max_completion_tokens", Json::number(value.to_double()))]
      },
      ..if temperature is Some(value) {
        [("temperature", Json::number(value))]
      },
      ..if top_p is Some(value) {
        [("top_p", Json::number(value))]
      },
      ..if frequency_penalty is Some(value) {
        [("frequency_penalty", Json::number(value))]
      },
      ..if presence_penalty is Some(value) {
        [("presence_penalty", Json::number(value))]
      },
      ..if options.seed is Some(value) {
        [("seed", Json::number(value.to_double()))]
      },
      ..if options.stop_sequences.length() > 0 {
        [
          (
            "stop",
            Json::array(
              [
                for stop in options.stop_sequences => Json::string(stop)
              ],
            ),
          ),
        ]
      },
      ..if openai_chat_response_format(
          options.response_format,
          provider_options.strict_json_schema,
        )
        is Some(value) {
        [("response_format", value)]
      },
      ..if provider_options.text_verbosity is Some(value) {
        [("verbosity", Json::string(value))]
      },
      ..if provider_options.store is Some(value) {
        [("store", Json::boolean(value))]
      },
      ..if provider_options.metadata is Some(value) {
        [("metadata", value)]
      },
      ..if provider_options.prediction is Some(value) {
        [("prediction", value)]
      },
      ..if reasoning_effort is Some(value) {
        [("reasoning_effort", Json::string(value))]
      },
      ..if service_tier is Some(value) {
        [("service_tier", Json::string(value))]
      },
      ..if provider_options.prompt_cache_key is Some(value) {
        [("prompt_cache_key", Json::string(value))]
      },
      ..if provider_options.prompt_cache_options is Some(value) {
        [("prompt_cache_options", value)]
      },
      ..if provider_options.prompt_cache_retention is Some(value) {
        [("prompt_cache_retention", Json::string(value))]
      },
      ..if provider_options.safety_identifier is Some(value) {
        [("safety_identifier", Json::string(value))]
      },
    ],
  )
  if tools.length() > 0 {
    fields["tools"] = Json::array(tools)
    match options.tool_choice {
      Some(choice) => fields["tool_choice"] = openai_chat_tool_choice(choice)
      None => ()
    }
  }
  { body: Json::object(fields), warnings }
}

///|
/// Encode an official OpenAI Chat Completions request.
pub fn encode_openai_chat_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  provider_name? : String = "openai.chat",
  stream? : Bool = true,
  preserve_reasoning? : Bool = false,
  include_usage? : Bool = true,
) -> Json raise {
  prepare_openai_chat_request(
    model_id, options, provider_name, stream, preserve_reasoning, include_usage,
  ).body
}
