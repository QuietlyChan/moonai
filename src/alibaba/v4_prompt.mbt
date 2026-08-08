///|
fn alibaba_v4_file_image_url(
  data : @provider.LanguageModelV4FileData,
  media_type : String,
) -> String raise {
  match data {
    @provider.V4FileUrl(value) => value
    @provider.V4FileData(value) =>
      "data:\{@provider_utils.resolve_full_media_type(media_type, value)};base64,\{value}"
    @provider.V4FileBytes(value) => {
      let encoded = @provider_utils.convert_bytes_to_base64(value)
      "data:\{@provider_utils.resolve_full_media_type(media_type, encoded)};base64,\{encoded}"
    }
    @provider.V4FileReference(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="file parts with provider references",
      )
    @provider.V4FileText(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="text file parts",
      )
  }
}

///|
fn alibaba_v4_user_content_part(
  part : @provider.LanguageModelV4PromptPart,
  cache_control : Json?,
) -> Json raise {
  let fields : Map[String, Json] = match part {
    @provider.V4PromptText(text~, ..) =>
      Map([("type", Json::string("text")), ("text", Json::string(text))])
    @provider.V4PromptFile(data~, media_type~, ..) => {
      guard @provider_utils.get_top_level_media_type(media_type) == "image" else {
        raise @provider.UnsupportedFunctionalityError(
          functionality="Only image file parts are supported",
        )
      }
      Map([
        ("type", Json::string("image_url")),
        (
          "image_url",
          ({ "url": alibaba_v4_file_image_url(data, media_type) } : Json),
        ),
      ])
    }
    _ =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="non-text/file parts in Alibaba user messages",
      )
  }
  if cache_control is Some(value) {
    fields["cache_control"] = value
  }
  Json::object(fields)
}

///|
fn alibaba_v4_tool_call(call : @provider.LanguageModelV4ToolCallPart) -> Json {
  {
    "id": call.tool_call_id,
    "type": "function",
    "function": { "name": call.tool_name, "arguments": call.input.stringify() },
  }
}

///|
fn alibaba_v4_file_data_json(data : @provider.LanguageModelV4FileData) -> Json {
  match data {
    @provider.V4FileData(value) => { "type": "data", "data": value }
    @provider.V4FileBytes(value) =>
      { "type": "data", "data": @provider_utils.convert_bytes_to_base64(value) }
    @provider.V4FileUrl(value) => { "type": "url", "url": value }
    @provider.V4FileReference(value) => {
      let fields : Map[String, Json] = Map([])
      for provider in value.providers() {
        if value.get(provider) is Some(id) {
          fields[provider] = Json::string(id)
        }
      }
      { "type": "reference", "reference": Json::object(fields) }
    }
    @provider.V4FileText(value) => { "type": "text", "text": value }
  }
}

///|
fn alibaba_v4_content_part_json(
  part : @provider.LanguageModelV4ToolResultContentPart,
) -> Json {
  let fields : Map[String, Json] = match part {
    @provider.V4ToolResultTextContent(text~, provider_options~) =>
      Map(
        [
          ("type", Json::string("text")),
          ("text", Json::string(text)),
          ..if provider_options.length() > 0 {
            [("providerOptions", Json::object(provider_options))]
          },
        ],
      )
    @provider.V4ToolResultFileContent(
      data~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      Map(
        [
          ("type", Json::string("file")),
          ("data", alibaba_v4_file_data_json(data)),
          ("mediaType", Json::string(media_type)),
          ..if filename is Some(value) {
            [("filename", Json::string(value))]
          },
          ..if provider_options.length() > 0 {
            [("providerOptions", Json::object(provider_options))]
          },
        ],
      )
    @provider.V4ToolResultCustomContent(provider_options~) =>
      Map(
        [
          ("type", Json::string("custom")),
          ..if provider_options.length() > 0 {
            [("providerOptions", Json::object(provider_options))]
          },
        ],
      )
  }
  Json::object(fields)
}

///|
fn alibaba_v4_tool_result_text(
  output : @provider.LanguageModelV4ToolResultOutput,
) -> String {
  match output {
    @provider.V4ToolResultTextOutput(value~, ..)
    | @provider.V4ToolResultErrorText(value~, ..) => value
    @provider.V4ToolResultExecutionDenied(reason~, ..) =>
      reason.unwrap_or("Tool call execution denied.")
    @provider.V4ToolResultJsonOutput(value~, ..)
    | @provider.V4ToolResultErrorJson(value~, ..) => value.stringify()
    @provider.V4ToolResultContentOutput(value~, ..) =>
      Json::array([ for part in value => alibaba_v4_content_part_json(part) ]).stringify()
  }
}

///|
/// Convert a V4 prompt using Alibaba's cache-control and multimodal rules.
fn alibaba_v4_prompt_converter(
  prompt : @provider.LanguageModelV4Prompt,
  _provider_name : String,
) -> @openai_compatible.OpenAICompatiblePromptConversion raise {
  let converted : Array[Json] = []
  let warnings : Array[@provider.Warning] = []
  let cache_breakpoints = Ref(0)
  for message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, provider_options~) => {
        let message_cache = record_alibaba_cache_control(
          alibaba_cache_control(provider_options),
          cache_breakpoints,
          warnings,
        )
        converted.push({
          "role": "system",
          "content": match message_cache {
            Some(value) =>
              Json::array([alibaba_text_block(content, Some(value))])
            None => Json::string(content)
          },
        })
      }
      @provider.V4UserMessage(content~, provider_options~) => {
        let message_cache = record_alibaba_cache_control(
          alibaba_cache_control(provider_options),
          cache_breakpoints,
          warnings,
        )
        let values : Array[Json] = []
        for index, part in content {
          let part_options = match part {
            @provider.V4PromptText(provider_options~, ..)
            | @provider.V4PromptReasoning(provider_options~, ..)
            | @provider.V4PromptReasoningFile(provider_options~, ..)
            | @provider.V4PromptCustom(provider_options~, ..)
            | @provider.V4PromptFile(provider_options~, ..) => provider_options
            @provider.V4PromptToolCall(value) => value.provider_options
            @provider.V4PromptToolResult(value) => value.provider_options
            @provider.V4PromptToolApprovalResponse(value) =>
              value.provider_options
          }
          let part_cache = record_alibaba_cache_control(
            alibaba_cache_control(part_options),
            cache_breakpoints,
            warnings,
          )
          let resolved_cache = if part_cache is Some(_) {
            part_cache
          } else if index == content.length() - 1 {
            message_cache
          } else {
            None
          }
          values.push(alibaba_v4_user_content_part(part, resolved_cache))
        }
        converted.push({ "role": "user", "content": values })
      }
      @provider.V4AssistantMessage(content~, provider_options~) => {
        let message_cache = record_alibaba_cache_control(
          alibaba_cache_control(provider_options),
          cache_breakpoints,
          warnings,
        )
        let text_builder = StringBuilder::new()
        let tool_calls : Array[Json] = []
        for part in content {
          match part {
            @provider.V4PromptText(text~, ..)
            | @provider.V4PromptReasoning(text~, ..) =>
              text_builder.write_string(text)
            @provider.V4PromptToolCall(value) =>
              tool_calls.push(alibaba_v4_tool_call(value))
            _ => ()
          }
        }
        let text_value = text_builder.to_string()
        let fields : Map[String, Json] = Map([
          ("role", Json::string("assistant")),
          (
            "content",
            match message_cache {
              Some(value) =>
                Json::array([alibaba_text_block(text_value, Some(value))])
              None if tool_calls.length() > 0 && text_value == "" =>
                Json::null()
              None => Json::string(text_value)
            },
          ),
        ])
        if tool_calls.length() > 0 {
          fields["tool_calls"] = Json::array(tool_calls)
        }
        converted.push(Json::object(fields))
      }
      @provider.V4ToolMessage(content~, provider_options~) => {
        let message_cache = record_alibaba_cache_control(
          alibaba_cache_control(provider_options),
          cache_breakpoints,
          warnings,
        )
        let tool_results : Array[@provider.LanguageModelV4ToolResultPart] = []
        for part in content {
          if part is @provider.V4PromptToolResult(value) {
            tool_results.push(value)
          }
        }
        for index, value in tool_results {
          let result_cache = record_alibaba_cache_control(
            alibaba_cache_control(value.provider_options),
            cache_breakpoints,
            warnings,
          )
          let resolved_cache = if result_cache is Some(_) {
            result_cache
          } else if index == tool_results.length() - 1 {
            message_cache
          } else {
            None
          }
          let content_value = alibaba_v4_tool_result_text(value.output)
          converted.push({
            "role": "tool",
            "tool_call_id": value.tool_call_id,
            "content": match resolved_cache {
              Some(cache) =>
                Json::array([alibaba_text_block(content_value, Some(cache))])
              None => Json::string(content_value)
            },
          })
        }
      }
    }
  }
  { messages: converted, warnings }
}
