///|
/// Convert a V4 prompt into Gemini generateContent contents. System messages
/// merge into the leading systemInstruction; assistant turns use the `model`
/// role; tool results become functionResponse parts.
fn google_convert_messages(
  prompt : @provider.LanguageModelV4Prompt,
) -> (Array[Json], String) raise {
  let contents : Array[Json] = []
  let system_instruction = StringBuilder()
  for message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, ..) => {
        if system_instruction.to_string() != "" {
          system_instruction.write_string("\n")
        }
        system_instruction.write_string(content)
      }
      @provider.V4UserMessage(content~, ..) => {
        let parts : Array[Json] = []
        for part in content {
          match part {
            @provider.V4PromptText(text~, ..) => parts.push({ "text": text })
            @provider.V4PromptFile(data~, media_type~, ..) =>
              match data {
                @provider.V4FileUrl(url) =>
                  parts.push({
                    "fileData": { "mimeType": media_type, "fileUri": url },
                  })
                @provider.V4FileData(payload) =>
                  parts.push({
                    "inlineData": { "mimeType": media_type, "data": payload },
                  })
                _ =>
                  raise @provider.UnsupportedFunctionalityError(
                    functionality="file parts with provider references",
                  )
              }
            _ => ()
          }
        }
        if parts.length() > 0 {
          contents.push({ "role": "user", "parts": Json::array(parts) })
        }
      }
      @provider.V4AssistantMessage(content~, ..) => {
        let parts : Array[Json] = []
        for part in content {
          match part {
            @provider.V4PromptText(text~, ..) if text != "" =>
              parts.push({ "text": text })
            @provider.V4PromptToolCall(call_part) =>
              parts.push({
                "functionCall": {
                  "name": call_part.tool_name,
                  "args": call_part.input,
                },
              })
            _ => ()
          }
        }
        if parts.length() > 0 {
          contents.push({ "role": "model", "parts": Json::array(parts) })
        }
      }
      @provider.V4ToolMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptToolResult(result_part) => {
              let output = match result_part.output {
                @provider.V4ToolResultTextOutput(value~, ..) =>
                  Json::string(value)
                @provider.V4ToolResultJsonOutput(value~, ..) => value
                @provider.V4ToolResultErrorText(value~, ..) =>
                  Json::string(value)
                @provider.V4ToolResultErrorJson(value~, ..) => value
                _ => Json::string("Tool call execution denied.")
              }
              contents.push({
                "role": "user",
                "parts": Json::array([
                  {
                    "functionResponse": {
                      "name": result_part.tool_name,
                      "response": { "output": output },
                    },
                  },
                ]),
              })
            }
            _ => ()
          }
        }
    }
  }
  (contents, system_instruction.to_string())
}

///|
fn google_map_finish_reason(
  raw : String?,
) -> @provider.LanguageModelV4FinishReason {
  let unified = match raw {
    Some("STOP") => @provider.V4FinishStop
    Some("MAX_TOKENS") => @provider.V4FinishLength
    Some("SAFETY") | Some("PROHIBITED_CONTENT") | Some("BLOCKLIST") =>
      @provider.V4FinishContentFilter
    Some("MALFORMED_FUNCTION_CALL") | Some("RECITATION") =>
      @provider.V4FinishError
    _ => @provider.V4FinishOther
  }
  { unified, raw, }
}

///|
fn google_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}
