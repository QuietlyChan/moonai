///|
priv struct PerplexityPreparedAgentRequest {
  body : Json
  warnings : Array[@provider.Warning]
}

///|
fn perplexity_agent_preset(model_id : String) -> String? {
  match model_id {
    "fast" | "low" | "medium" | "high" | "xhigh" => Some(model_id)
    _ => None
  }
}

///|
fn perplexity_agent_function_tools(
  tools : Array[@provider.LanguageModelV4Tool],
  warnings : Array[@provider.Warning],
) -> Array[Json] {
  let result : Array[Json] = []
  for tool in tools {
    match tool {
      @provider.V4FunctionTool(value) => {
        let fields : Map[String, Json] = Map(
          [
            ("type", Json::string("function")),
            ("name", Json::string(value.name)),
            ("parameters", value.input_schema),
            ..if value.description is Some(description) {
              [("description", Json::string(description))]
            },
            ..if value.strict is Some(strict) {
              [("strict", Json::boolean(strict))]
            },
          ],
        )
        result.push(Json::object(fields))
      }
      @provider.V4ProviderTool(value) =>
        warnings.push(
          @provider.Warning::unsupported("provider-defined tool \{value.name}"),
        )
    }
  }
  result
}

///|
fn perplexity_thought_signature(provider_options : Map[String, Json]) -> Json? {
  match provider_options.get("perplexity") {
    Some({ "thoughtSignature": String(value), .. }) => Some(Json::string(value))
    _ => None
  }
}

///|
fn perplexity_tool_output_text(
  output : @provider.LanguageModelV4ToolResultOutput,
) -> String raise {
  match output {
    @provider.V4ToolResultTextOutput(value~, ..) => value
    @provider.V4ToolResultErrorText(value~, ..) => value
    @provider.V4ToolResultJsonOutput(value~, ..) => value.stringify()
    @provider.V4ToolResultErrorJson(value~, ..) => value.stringify()
    @provider.V4ToolResultExecutionDenied(reason~, ..) =>
      reason.unwrap_or("Tool call execution denied.")
    @provider.V4ToolResultContentOutput(value~, ..) => {
      let result : Array[String] = []
      for part in value {
        match part {
          @provider.V4ToolResultTextContent(text~, ..) => result.push(text)
          _ =>
            raise @provider.UnsupportedFunctionalityError(
              functionality="file and custom tool result content",
            )
        }
      }
      result.join("")
    }
  }
}

///|
fn perplexity_agent_file_content(
  data : @provider.LanguageModelV4FileData,
  media_type : String,
) -> Json raise {
  guard @provider_utils.get_top_level_media_type(media_type) == "image" else {
    raise @provider.UnsupportedFunctionalityError(
      functionality="file part media type \{media_type}",
    )
  }
  let image_url = match data {
    @provider.V4FileUrl(url) => url
    @provider.V4FileData(base64) => {
      let resolved_media_type = @provider_utils.resolve_full_media_type(
        media_type, base64,
      ) catch {
        _ =>
          raise @provider.UnsupportedFunctionalityError(
            functionality="image file without a resolvable media subtype",
          )
      }
      "data:\{resolved_media_type};base64,\{base64}"
    }
    @provider.V4FileBytes(bytes) => {
      let base64 = @provider_utils.convert_bytes_to_base64(bytes)
      let resolved_media_type = @provider_utils.resolve_full_media_type(
        media_type, base64,
      ) catch {
        _ =>
          raise @provider.UnsupportedFunctionalityError(
            functionality="image file without a resolvable media subtype",
          )
      }
      "data:\{resolved_media_type};base64,\{base64}"
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
  { "type": "input_image", "image_url": Json::string(image_url) }
}

///|
fn perplexity_agent_prompt_input(
  prompt : @provider.LanguageModelV4Prompt,
) -> (Array[Json], Array[@provider.Warning]) raise {
  let input : Array[Json] = []
  let warnings : Array[@provider.Warning] = []
  for message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, ..) =>
        input.push({
          "type": "message",
          "role": "system",
          "content": Json::string(content),
        })
      @provider.V4UserMessage(content~, ..) => {
        let converted : Array[Json] = []
        for part in content {
          match part {
            @provider.V4PromptText(text~, ..) =>
              converted.push({
                "type": "input_text",
                "text": Json::string(text),
              })
            @provider.V4PromptFile(data~, media_type~, ..) =>
              converted.push(perplexity_agent_file_content(data, media_type))
            _ =>
              raise @provider.UnsupportedFunctionalityError(
                functionality="non-text user prompt parts other than images",
              )
          }
        }
        let text_only = converted.all(part => {
          part is { "type": "input_text", .. }
        })
        let body_content : Json = if text_only {
          Json::string(
            converted
            .map(part => {
              @provider_utils.json_string_field(part, "text").unwrap_or("")
            })
            .join(""),
          )
        } else {
          Json::array(converted)
        }
        input.push({
          "type": "message",
          "role": "user",
          "content": body_content,
        })
      }
      @provider.V4AssistantMessage(content~, ..) => {
        let text : Array[String] = []
        let tools : Array[Json] = []
        for part in content {
          match part {
            @provider.V4PromptText(text=value, ..) => text.push(value)
            @provider.V4PromptReasoning(_, ..) =>
              warnings.push(
                @provider.Warning::unsupported("reasoning content in prompt"),
              )
            @provider.V4PromptToolCall(call) => {
              let fields : Map[String, Json] = Map(
                [
                  ("type", Json::string("function_call")),
                  ("call_id", Json::string(call.tool_call_id)),
                  ("name", Json::string(call.tool_name)),
                  (
                    "arguments",
                    Json::string(
                      if call.input is Null {
                        "{}"
                      } else {
                        call.input.stringify()
                      },
                    ),
                  ),
                  ..if perplexity_thought_signature(call.provider_options)
                    is Some(signature) {
                    [("thought_signature", signature)]
                  },
                ],
              )
              tools.push(Json::object(fields))
            }
            @provider.V4PromptToolResult(result) => {
              let fields : Map[String, Json] = Map(
                [
                  ("type", Json::string("function_call_output")),
                  ("call_id", Json::string(result.tool_call_id)),
                  (
                    "output",
                    Json::string(perplexity_tool_output_text(result.output)),
                  ),
                  ..if result.tool_name != "" {
                    [("name", Json::string(result.tool_name))]
                  },
                  ..if perplexity_thought_signature(result.provider_options)
                    is Some(signature) {
                    [("thought_signature", signature)]
                  },
                ],
              )
              tools.push(Json::object(fields))
            }
            @provider.V4PromptToolApprovalResponse(_) =>
              raise @provider.UnsupportedFunctionalityError(
                functionality="tool approval responses",
              )
            @provider.V4PromptFile(_)
            | @provider.V4PromptReasoningFile(_)
            | @provider.V4PromptCustom(_) =>
              raise @provider.UnsupportedFunctionalityError(
                functionality="assistant non-text prompt parts",
              )
          }
        }
        let joined = text.join("")
        if joined != "" {
          input.push({
            "type": "message",
            "role": "assistant",
            "content": Json::string(joined),
          })
        }
        for tool in tools {
          input.push(tool)
        }
      }
      @provider.V4ToolMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptToolResult(result) => {
              let fields : Map[String, Json] = Map(
                [
                  ("type", Json::string("function_call_output")),
                  ("call_id", Json::string(result.tool_call_id)),
                  (
                    "output",
                    Json::string(perplexity_tool_output_text(result.output)),
                  ),
                  ..if result.tool_name != "" {
                    [("name", Json::string(result.tool_name))]
                  },
                  ..if perplexity_thought_signature(result.provider_options)
                    is Some(signature) {
                    [("thought_signature", signature)]
                  },
                ],
              )
              input.push(Json::object(fields))
            }
            @provider.V4PromptToolApprovalResponse(_) =>
              raise @provider.UnsupportedFunctionalityError(
                functionality="tool approval responses",
              )
            _ =>
              raise @provider.UnsupportedFunctionalityError(
                functionality="tool messages without a tool result",
              )
          }
        }
    }
  }
  (input, warnings)
}

///|
fn perplexity_agent_reasoning(
  reasoning : @provider.LanguageModelV4ReasoningEffort,
  warnings : Array[@provider.Warning],
) -> Json? {
  match reasoning {
    @provider.V4ReasoningProviderDefault => None
    @provider.V4ReasoningNone => {
      warnings.push(
        @provider.Warning::Compatibility(
          feature="reasoning",
          details="Reasoning cannot be disabled in the Perplexity Agent API; using the lowest effort.",
        ),
      )
      Some({ "effort": "minimal" })
    }
    @provider.V4ReasoningMinimal => Some({ "effort": "minimal" })
    @provider.V4ReasoningLow => Some({ "effort": "low" })
    @provider.V4ReasoningMedium => Some({ "effort": "medium" })
    @provider.V4ReasoningHigh => Some({ "effort": "high" })
    @provider.V4ReasoningXHigh => Some({ "effort": "xhigh" })
    @provider.V4ReasoningMax => {
      warnings.push(
        @provider.Warning::Compatibility(
          feature="reasoning",
          details="Perplexity supports reasoning effort through xhigh; max was mapped to xhigh.",
        ),
      )
      Some({ "effort": "xhigh" })
    }
  }
}

///|
fn PerplexityLanguageModel::prepare_agent_request(
  self : PerplexityLanguageModel,
  options : @provider.LanguageModelV4CallOptions,
) -> PerplexityPreparedAgentRequest raise {
  let warnings : Array[@provider.Warning] = []
  for
    warning in [
      if options.top_k is Some(_) {
        Some(@provider.Warning::unsupported("topK"))
      } else {
        None
      },
      if options.frequency_penalty is Some(_) {
        Some(@provider.Warning::unsupported("frequencyPenalty"))
      } else {
        None
      },
      if options.presence_penalty is Some(_) {
        Some(@provider.Warning::unsupported("presencePenalty"))
      } else {
        None
      },
      if options.stop_sequences.length() > 0 {
        Some(@provider.Warning::unsupported("stopSequences"))
      } else {
        None
      },
      if options.seed is Some(_) {
        Some(@provider.Warning::unsupported("seed"))
      } else {
        None
      },
    ] {
    match warning {
      Some(value) => warnings.push(value)
      None => ()
    }
  }
  let (input, input_warnings) = perplexity_agent_prompt_input(options.prompt)
  for warning in input_warnings {
    warnings.push(warning)
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name="perplexity",
    reserved_fields=["input", "model", "preset", "stream"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let native_tools = match resolution.values.get("tools") {
    Some(Array(values)) => values.copy()
    Some(_) => {
      warnings.push(
        @provider.Warning::Compatibility(
          feature="providerOptions.tools",
          details="Expected an array of Perplexity Agent API tools; the value was ignored.",
        ),
      )
      []
    }
    None => []
  }
  let tools : Array[Json] = []
  if options.tool_choice != Some(@provider.V4ToolChoiceNone) {
    let function_tools = perplexity_agent_function_tools(
      options.tools,
      warnings,
    )
    for tool in native_tools {
      tools.push(tool)
    }
    for tool in function_tools {
      tools.push(tool)
    }
  }
  match options.tool_choice {
    Some(@provider.V4ToolChoiceRequired)
    | Some(@provider.V4ToolChoiceTool(_)) =>
      warnings.push(
        @provider.Warning::Unsupported(
          feature="toolChoice",
          details="The Perplexity Agent API selects tools automatically.",
        ),
      )
    _ => ()
  }
  let body : Map[String, Json] = Map([])
  for entry in resolution.values.iter2() {
    if entry.0 != "tools" {
      body[entry.0] = entry.1
    }
  }
  body.remove("model")
  body.remove("preset")
  body["input"] = Json::array(input)
  if perplexity_agent_preset(self.model_id) is Some(preset) {
    body["preset"] = Json::string(preset)
  } else {
    body["model"] = Json::string(self.model_id)
  }
  if options.max_output_tokens is Some(value) {
    body["max_output_tokens"] = Json::number(value.to_double())
  }
  if options.temperature is Some(value) {
    body["temperature"] = Json::number(value)
  }
  if options.top_p is Some(value) {
    body["top_p"] = Json::number(value)
  }
  match options.tool_choice {
    Some(@provider.V4ToolChoiceNone) =>
      body["max_tool_calls"] = Json::number(0.0)
    _ => ()
  }
  if options.response_format is @provider.V4ResponseJson(format) {
    match format.schema {
      Some(schema) => {
        let json_schema : Map[String, Json] = Map([
          ("name", Json::string(format.name.unwrap_or("response"))),
          ("schema", schema),
          ("strict", Json::boolean(true)),
        ])
        if format.description is Some(description) {
          json_schema["description"] = Json::string(description)
        }
        body["response_format"] = {
          "type": "json_schema",
          "json_schema": Json::object(json_schema),
        }
      }
      None =>
        warnings.push(
          @provider.Warning::unsupported(
            "JSON response format without a schema",
          ),
        )
    }
  }
  let provider_reasoning = body.get("reasoning")
  if provider_reasoning is None {
    match perplexity_agent_reasoning(options.reasoning, warnings) {
      Some(reasoning) => body["reasoning"] = reasoning
      None => ()
    }
  }
  if tools.length() > 0 {
    body["tools"] = Json::array(tools)
  } else if options.tool_choice is Some(@provider.V4ToolChoiceNone) {
    body.remove("tools")
  }
  { body: Json::object(body), warnings, }
}
