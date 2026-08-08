///|
fn input_text(text : String) -> Json {
  { "type": "input_text", "text": text }
}

///|
fn data_uri(media_type : String, data : String) -> String {
  "data:\{media_type};base64,\{data}"
}

///|
fn output_text(text : String) -> Json {
  { "type": "output_text", "text": text }
}

///|
fn message_item(role : String, content : Array[Json]) -> Json {
  Json::object(
    Map([
      ("type", Json::string("message")),
      ("role", Json::string(role)),
      ("content", Json::array(content)),
    ]),
  )
}

///|
/// Open Responses input obtained from the provider-neutral V4 prompt.
priv struct OpenResponsesV4PromptConversion {
  input : Array[Json]
  instructions : String?
  warnings : Array[@provider.Warning]
}

///|
fn v4_file_to_open_responses_input(
  data : @provider.LanguageModelV4FileData,
  media_type : String,
  filename : String?,
) -> Json raise {
  match data {
    @provider.V4FileReference(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="file parts with provider references",
      )
    @provider.V4FileText(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="text file parts",
      )
    @provider.V4FileUrl(url) =>
      if @provider_utils.get_top_level_media_type(media_type) == "image" {
        { "type": "input_image", "image_url": url }
      } else {
        { "type": "input_file", "file_url": url }
      }
    @provider.V4FileData(data) =>
      v4_base64_file_to_open_responses_input(data, media_type, filename)
    @provider.V4FileBytes(data) =>
      v4_base64_file_to_open_responses_input(
        @provider_utils.convert_bytes_to_base64(data),
        media_type,
        filename,
      )
  }
}

///|
fn v4_base64_file_to_open_responses_input(
  data : String,
  media_type : String,
  filename : String?,
) -> Json raise {
  let full_media_type = @provider_utils.resolve_full_media_type(
    media_type, data,
  )
  if @provider_utils.get_top_level_media_type(media_type) == "image" {
    { "type": "input_image", "image_url": data_uri(full_media_type, data) }
  } else {
    {
      "type": "input_file",
      "filename": filename.unwrap_or("data"),
      "file_data": data_uri(full_media_type, data),
    }
  }
}

///|
fn v4_user_content_to_open_responses(
  content : Array[@provider.LanguageModelV4PromptPart],
) -> Array[Json] raise {
  let converted : Array[Json] = []
  for part in content {
    match part {
      @provider.V4PromptText(text~, ..) => converted.push(input_text(text))
      @provider.V4PromptFile(data~, media_type~, filename~, ..) =>
        converted.push(
          v4_file_to_open_responses_input(data, media_type, filename),
        )
      _ =>
        raise @provider.UnsupportedFunctionalityError(
          functionality="non-text/file parts in Open Responses user messages",
        )
    }
  }
  converted
}

///|
fn v4_tool_result_content_part_to_open_responses(
  part : @provider.LanguageModelV4ToolResultContentPart,
  warnings : Array[@provider.Warning],
) -> Json? raise {
  match part {
    @provider.V4ToolResultTextContent(text~, ..) => Some(input_text(text))
    @provider.V4ToolResultFileContent(data~, media_type~, filename~, ..) =>
      match data {
        @provider.V4FileData(value) =>
          Some(
            v4_base64_file_to_open_responses_input(value, media_type, filename),
          )
        @provider.V4FileBytes(value) =>
          Some(
            v4_base64_file_to_open_responses_input(
              @provider_utils.convert_bytes_to_base64(value),
              media_type,
              filename,
            ),
          )
        @provider.V4FileUrl(url) =>
          Some(
            if @provider_utils.get_top_level_media_type(media_type) == "image" {
              ({ "type": "input_image", "image_url": url } : Json)
            } else {
              ({ "type": "input_file", "file_url": url } : Json)
            },
          )
        @provider.V4FileReference(_) | @provider.V4FileText(_) => {
          let data_type = if data is @provider.V4FileReference(_) {
            "reference"
          } else {
            "text"
          }
          warnings.push(
            @provider.Other(
              message="unsupported tool content part type: file with data type: \{data_type}",
            ),
          )
          None
        }
      }
    @provider.V4ToolResultCustomContent(..) => {
      warnings.push(
        @provider.Other(message="unsupported tool content part type: custom"),
      )
      None
    }
  }
}

///|
fn v4_tool_result_output_to_open_responses(
  output : @provider.LanguageModelV4ToolResultOutput,
  warnings : Array[@provider.Warning],
) -> Json raise {
  match output {
    @provider.V4ToolResultTextOutput(value~, ..)
    | @provider.V4ToolResultErrorText(value~, ..) => Json::string(value)
    @provider.V4ToolResultJsonOutput(value~, ..)
    | @provider.V4ToolResultErrorJson(value~, ..) =>
      Json::string(value.stringify())
    @provider.V4ToolResultExecutionDenied(reason~, ..) =>
      Json::string(reason.unwrap_or("Tool call execution denied."))
    @provider.V4ToolResultContentOutput(value~, ..) => {
      let converted : Array[Json] = []
      for part in value {
        match v4_tool_result_content_part_to_open_responses(part, warnings) {
          Some(item) => converted.push(item)
          None => ()
        }
      }
      Json::array(converted)
    }
  }
}

///|
fn v4_tool_result_to_open_responses(
  result : @provider.LanguageModelV4ToolResultPart,
  warnings : Array[@provider.Warning],
) -> Json raise {
  {
    "type": "function_call_output",
    "call_id": result.tool_call_id,
    "output": v4_tool_result_output_to_open_responses(result.output, warnings),
  }
}

///|
/// Convert a V4 prompt without routing through the pre-V4 ChatModel prompt.
fn convert_v4_prompt_to_open_responses(
  prompt : @provider.LanguageModelV4Prompt,
) -> OpenResponsesV4PromptConversion raise {
  let input : Array[Json] = []
  let instructions : Array[String] = []
  let warnings : Array[@provider.Warning] = []
  for message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, ..) => instructions.push(content)
      @provider.V4UserMessage(content~, ..) =>
        input.push(
          message_item("user", v4_user_content_to_open_responses(content)),
        )
      @provider.V4AssistantMessage(content~, ..) => {
        let assistant_content : Array[Json] = []
        let tool_calls : Array[@provider.LanguageModelV4ToolCallPart] = []
        for part in content {
          match part {
            @provider.V4PromptText(text~, ..) =>
              assistant_content.push(output_text(text))
            @provider.V4PromptToolCall(call) => tool_calls.push(call)
            _ => ()
          }
        }
        if assistant_content.length() > 0 {
          input.push(message_item("assistant", assistant_content))
        }
        for call in tool_calls {
          input.push({
            "type": "function_call",
            "call_id": call.tool_call_id,
            "name": call.tool_name,
            "arguments": match call.input {
              String(value) => value
              value => value.stringify()
            },
          })
        }
      }
      @provider.V4ToolMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptToolResult(result) =>
              input.push(v4_tool_result_to_open_responses(result, warnings))
            _ => ()
          }
        }
    }
  }
  {
    input,
    instructions: if instructions.length() == 0 {
      None
    } else {
      Some(instructions.join("\n"))
    },
    warnings,
  }
}
