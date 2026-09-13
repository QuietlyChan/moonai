///|
priv struct MoonshotV4PromptConversion {
  messages : Array[Json]
  warnings : Array[@provider.Warning]
}

///|
fn moonshot_supported_image_media_type(media_type : String) -> Bool {
  media_type == "image/jpeg" ||
  media_type == "image/png" ||
  media_type == "image/gif" ||
  media_type == "image/webp" ||
  media_type == "image/bmp" ||
  media_type == "image/heic" ||
  media_type == "image/heif"
}

///|
fn moonshot_supported_video_media_type(media_type : String) -> Bool {
  media_type == "video/mp4" ||
  media_type == "video/mpeg" ||
  media_type == "video/mov" ||
  media_type == "video/avi" ||
  media_type == "video/x-flv" ||
  media_type == "video/mpg" ||
  media_type == "video/webm" ||
  media_type == "video/wmv" ||
  media_type == "video/3gpp"
}

///|
/// Build the URL for a url/data file part. Moonshot AI does not fetch
/// external URLs for inline data; the AI SDK downloads and inlines them, so
/// URL parts pass through verbatim and data parts become data URLs.
fn moonshot_media_url(
  data~ : @provider.LanguageModelV4FileData,
  media_type~ : String,
  top_level~ : String,
  supported_check~ : (String) -> Bool,
) -> String raise {
  let resolved = match data {
    @provider.V4FileUrl(url) =>
      if supported_check(media_type) ||
        media_type == top_level ||
        media_type == "\{top_level}/*" {
        url
      } else {
        raise @provider.UnsupportedFunctionalityError(
          functionality="file part media type \{media_type}",
        )
      }
    @provider.V4FileData(base64) => {
      let full = @provider_utils.resolve_full_media_type(media_type, base64)
      guard supported_check(full) else {
        raise @provider.UnsupportedFunctionalityError(
          functionality="file part media type \{media_type}",
        )
      }
      "data:\{full};base64,\{base64}"
    }
    @provider.V4FileBytes(bytes) => {
      let base64 = @provider_utils.convert_bytes_to_base64(bytes)
      let full = @provider_utils.resolve_full_media_type(media_type, base64)
      guard supported_check(full) else {
        raise @provider.UnsupportedFunctionalityError(
          functionality="file part media type \{media_type}",
        )
      }
      "data:\{full};base64,\{base64}"
    }
    _ =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="file part data type reference",
      )
  }
  resolved
}

///|
fn moonshot_file_part_content(
  data~ : @provider.LanguageModelV4FileData,
  media_type~ : String,
) -> Json raise {
  let top_level = @provider_utils.get_top_level_media_type(media_type)
  match data {
    @provider.V4FileReference(reference) => {
      guard top_level == "image" || top_level == "video" else {
        raise @provider.UnsupportedFunctionalityError(
          functionality="file part media type \{media_type}",
        )
      }
      let reference_id = @provider_utils.resolve_provider_reference(
        reference, "moonshotai",
      )
      guard reference_id.has_prefix("ms://") else {
        raise @provider.UnsupportedFunctionalityError(
          functionality="Moonshot file provider references without an ms:// URL",
        )
      }
      if top_level == "image" {
        { "type": "image_url", "image_url": { "url": reference_id } }
      } else {
        { "type": "video_url", "video_url": { "url": reference_id } }
      }
    }
    @provider.V4FileText(text) => {
      guard top_level == "text" else {
        raise @provider.UnsupportedFunctionalityError(
          functionality="file part media type \{media_type}",
        )
      }
      { "type": "text", "text": text }
    }
    _ =>
      if top_level == "image" {
        let url = moonshot_media_url(
          data~,
          media_type~,
          top_level~,
          supported_check=moonshot_supported_image_media_type,
        )
        { "type": "image_url", "image_url": { "url": url } }
      } else if top_level == "video" {
        let url = moonshot_media_url(
          data~,
          media_type~,
          top_level~,
          supported_check=moonshot_supported_video_media_type,
        )
        { "type": "video_url", "video_url": { "url": url } }
      } else if top_level == "text" {
        let text = match data {
          @provider.V4FileUrl(url) => url
          @provider.V4FileData(base64) => @utf8.decode(@base64.decode(base64))
          @provider.V4FileBytes(bytes) => @utf8.decode(bytes)
          _ => ""
        }
        { "type": "text", "text": text }
      } else {
        raise @provider.UnsupportedFunctionalityError(
          functionality="file part media type \{media_type}",
        )
      }
  }
}

///|
/// Read a string option from a message's Moonshot AI provider options.
fn moonshot_message_provider_string(
  options : Map[String, Json],
  field~ : String,
) -> String? {
  match options.get("moonshotai") {
    Some(Object(values)) =>
      match values.get(field) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
/// Read a boolean option from a message's Moonshot AI provider options.
fn moonshot_message_provider_bool(
  options : Map[String, Json],
  field~ : String,
) -> Bool? {
  match options.get("moonshotai") {
    Some(Object(values)) =>
      match values.get(field) {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
/// Parse function tools attached to a system message for Kimi K3 dynamic
/// tool loading.
fn moonshot_message_dynamic_tools(
  options : Map[String, Json],
) -> Array[@provider.LanguageModelV4Tool]? {
  match options.get("moonshotai") {
    Some(Object(values)) =>
      match values.get("tools") {
        Some(Array(raw_tools)) => {
          let tools : Array[@provider.LanguageModelV4Tool] = []
          for raw in raw_tools {
            match raw {
              {
                "type": String("function"),
                "name": String(name),
                "inputSchema": Object(input_schema),
                ..
              } => {
                let description = match raw {
                  { "description": String(value), .. } => Some(value)
                  _ => None
                }
                let strict = match raw {
                  { "strict": true, .. } => Some(true)
                  { "strict": false, .. } => Some(false)
                  _ => None
                }
                tools.push(
                  @provider.LanguageModelV4Tool::function(
                    name,
                    Json::object(input_schema),
                    description?,
                    strict?,
                  ),
                )
              }
              _ => ()
            }
          }
          Some(tools)
        }
        _ => None
      }
    _ => None
  }
}

///|
fn moonshot_v4_tool_call_json(
  call : @provider.LanguageModelV4ToolCallPart,
) -> Json {
  {
    "id": call.tool_call_id,
    "type": "function",
    "function": { "name": call.tool_name, "arguments": call.input.stringify() },
  }
}

///|
fn moonshot_v4_tool_result_text(
  output : @provider.LanguageModelV4ToolResultOutput,
) -> String {
  match output {
    @provider.V4ToolResultTextOutput(value~, ..)
    | @provider.V4ToolResultErrorText(value~, ..) => value
    @provider.V4ToolResultExecutionDenied(reason~, ..) =>
      reason.unwrap_or("Tool call execution denied.")
    @provider.V4ToolResultJsonOutput(value~, ..)
    | @provider.V4ToolResultErrorJson(value~, ..) => value.stringify()
    @provider.V4ToolResultContentOutput(value~, ..) => {
      let text = StringBuilder()
      for part in value {
        match part {
          @provider.V4ToolResultTextContent(text=value, ..) => {
            if text.to_string().length() > 0 {
              text.write_string("\n")
            }
            text.write_string(value)
          }
          _ => ()
        }
      }
      text.to_string()
    }
  }
}

///|
/// Read the provider-options map carried by any V4 prompt message variant.
fn moonshot_v4_message_provider_options(
  message : @provider.LanguageModelV4Message,
) -> Map[String, Json] {
  match message {
    @provider.V4SystemMessage(provider_options~, ..) => provider_options
    @provider.V4UserMessage(provider_options~, ..) => provider_options
    @provider.V4AssistantMessage(provider_options~, ..) => provider_options
    @provider.V4ToolMessage(provider_options~, ..) => provider_options
  }
}

///|
/// Convert the provider V4 prompt into Moonshot AI Chat messages.
fn convert_v4_prompt_to_moonshot(
  prompt : @provider.LanguageModelV4Prompt,
  model_id~ : String,
  provider_name~ : String,
  response_format~ : Json?,
) -> MoonshotV4PromptConversion raise {
  let messages : Array[Json] = []
  let warnings : Array[@provider.Warning] = []
  let model_family = get_moonshot_ai_model_family(model_id)
  for index, message in prompt.messages {
    let message_options = moonshot_v4_message_provider_options(message)
    let name = moonshot_message_provider_string(message_options, field="name")
    let partial = moonshot_message_provider_bool(
        message_options,
        field="partial",
      ) ==
      Some(true)
    let dynamic_tools = moonshot_message_dynamic_tools(message_options)
    if partial && !(message is @provider.V4AssistantMessage(_)) {
      raise @provider.InvalidPromptError(
        message="Moonshot AI Partial Mode requires `partial: true` on an assistant message.",
      )
    }
    if dynamic_tools is Some(_) && !(message is @provider.V4SystemMessage(_)) {
      raise @provider.InvalidPromptError(
        message="Moonshot dynamic tools must be configured on a system message.",
      )
    }
    match message {
      @provider.V4SystemMessage(content~, provider_options~) => {
        ignore(provider_options)
        if dynamic_tools is Some(tools) {
          guard content == "" else {
            raise @provider.InvalidPromptError(
              message="A Moonshot dynamic-tool system message must use empty content because the API forbids content alongside tools.",
            )
          }
          if model_family is (KimiK3 | Unknown) {
            let prepared = prepare_moonshot_tools(
              tools~,
              tool_choice=None,
              model_id~,
            )
            for warning in prepared.warnings {
              warnings.push(warning)
            }
            let tool_values : Array[Json] = match prepared.tools {
              Some(values) => values
              None => []
            }
            messages.push({
              "role": "system",
              "tools": Json::array(tool_values),
            })
          } else {
            warnings.push(
              @provider.Warning::Unsupported(
                feature="dynamic tool loading for model \"\{model_id}\"",
                details="Moonshot documents dynamic tool loading only for Kimi K3. The dynamic system message has been omitted.",
              ),
            )
          }
          continue
        }
        let fields : Map[String, Json] = Map([
          ("role", Json::string("system")),
          ("content", Json::string(content)),
        ])
        if name is Some(value) {
          fields["name"] = Json::string(value)
        }
        messages.push(Json::object(fields))
      }
      @provider.V4UserMessage(content~, provider_options~) => {
        ignore(provider_options)
        let has_single_text = content.length() == 1 &&
          content[0] is @provider.V4PromptText(_)
        if has_single_text {
          for part in content {
            match part {
              @provider.V4PromptText(text=value, ..) => {
                let fields : Map[String, Json] = Map([
                  ("role", Json::string("user")),
                  ("content", Json::string(value)),
                ])
                if name is Some(value) {
                  fields["name"] = Json::string(value)
                }
                messages.push(Json::object(fields))
              }
              _ => ()
            }
          }
          continue
        }
        let parts : Array[Json] = []
        for part in content {
          match part {
            @provider.V4PromptText(text=value, ..) =>
              parts.push({ "type": "text", "text": value })
            @provider.V4PromptFile(data~, media_type~, ..) =>
              parts.push(moonshot_file_part_content(data~, media_type~))
            _ => ()
          }
        }
        let fields : Map[String, Json] = Map([
          ("role", Json::string("user")),
          ("content", Json::array(parts)),
        ])
        if name is Some(value) {
          fields["name"] = Json::string(value)
        }
        messages.push(Json::object(fields))
      }
      @provider.V4AssistantMessage(content~, provider_options~) => {
        ignore(provider_options)
        if partial {
          guard index == prompt.messages.length() - 1 else {
            raise @provider.InvalidPromptError(
              message="Moonshot AI Partial Mode requires the partial assistant message to be the final message.",
            )
          }
          match response_format {
            Some({ "type": String("json_object"), .. }) =>
              raise @provider.InvalidPromptError(
                message="Moonshot AI Partial Mode cannot be combined with JSON object response format.",
              )
            _ => ()
          }
        }
        let text = StringBuilder()
        let reasoning = StringBuilder()
        let tool_calls : Array[Json] = []
        for part in content {
          match part {
            @provider.V4PromptText(text=value, ..) => text.write_string(value)
            @provider.V4PromptReasoning(text=value, ..) =>
              reasoning.write_string(value)
            @provider.V4PromptToolCall(call) =>
              tool_calls.push(moonshot_v4_tool_call_json(call))
            _ => ()
          }
        }
        let fields : Map[String, Json] = Map([
          ("role", Json::string("assistant")),
          (
            "content",
            if tool_calls.length() > 0 {
              if text.to_string() == "" {
                Json::null()
              } else {
                Json::string(text.to_string())
              }
            } else {
              Json::string(text.to_string())
            },
          ),
        ])
        if name is Some(value) {
          fields["name"] = Json::string(value)
        }
        if partial {
          fields["partial"] = Json::boolean(true)
        }
        if reasoning.to_string() != "" {
          fields["reasoning_content"] = Json::string(reasoning.to_string())
        }
        if tool_calls.length() > 0 {
          fields["tool_calls"] = Json::array(tool_calls)
        }
        messages.push(Json::object(fields))
      }
      @provider.V4ToolMessage(content~, ..) => {
        if name is Some(_) {
          warnings.push(
            @provider.Warning::Unsupported(
              feature="message name on tool messages",
              details="Moonshot AI does not support message names on tool messages.",
            ),
          )
        }
        for part in content {
          match part {
            @provider.V4PromptToolResult(result) =>
              messages.push({
                "role": "tool",
                "tool_call_id": result.tool_call_id,
                "content": moonshot_v4_tool_result_text(result.output),
              })
            @provider.V4PromptToolApprovalResponse(_) => ()
            _ => ()
          }
        }
      }
    }
  }
  ignore(provider_name)
  { messages, warnings, }
}
