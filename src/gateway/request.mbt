///|
/// Serialize a V4 prompt into the gateway's JSON wire shape. The gateway
/// accepts the V4 call options object as-is (camelCase).
fn gateway_encode_prompt(
  prompt : @provider.LanguageModelV4Prompt,
) -> Json raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  let messages : Array[Json] = []
  for message in prompt.messages {
    match message {
      @provider.V4SystemMessage(content~, ..) =>
        messages.push({ "role": "system", "content": content })
      @provider.V4UserMessage(content~, ..) =>
        messages.push({
          "role": "user",
          "content": gateway_encode_prompt_parts(content),
        })
      @provider.V4AssistantMessage(content~, ..) =>
        messages.push({
          "role": "assistant",
          "content": gateway_encode_prompt_parts(content),
        })
      @provider.V4ToolMessage(content~, ..) =>
        messages.push({
          "role": "tool",
          "content": gateway_encode_prompt_parts(content),
        })
    }
  }
  { "messages": Json::array(messages) }
}

///|
fn gateway_encode_prompt_parts(
  parts : Array[@provider.LanguageModelV4PromptPart],
) -> Json {
  let encoded : Array[Json] = []
  for part in parts {
    match part {
      @provider.V4PromptText(text~, ..) =>
        encoded.push({ "type": "text", "text": text })
      @provider.V4PromptReasoning(text~, ..) =>
        encoded.push({ "type": "reasoning", "text": text })
      @provider.V4PromptFile(data~, media_type~, filename~, ..) => {
        let file : Map[String, Json] = Map([
          ("mediaType", Json::string(media_type)),
        ])
        match data {
          @provider.V4FileUrl(url) =>
            file["data"] = { "type": "url", "url": url }
          @provider.V4FileData(payload) =>
            file["data"] = { "type": "data", "data": payload }
          @provider.V4FileText(text) =>
            file["data"] = { "type": "text", "text": text }
          _ => ()
        }
        if filename is Some(value) {
          file["filename"] = Json::string(value)
        }
        file["type"] = Json::string("file")
        encoded.push(Json::object(file))
      }
      @provider.V4PromptToolCall(call_part) =>
        encoded.push({
          "type": "tool-call",
          "toolCallId": call_part.tool_call_id,
          "toolName": call_part.tool_name,
          "input": call_part.input,
        })
      @provider.V4PromptToolResult(result_part) => {
        let output_type = match result_part.output {
          @provider.V4ToolResultJsonOutput(..) => "json"
          _ => "text"
        }
        let output_value = match result_part.output {
          @provider.V4ToolResultTextOutput(value~, ..) => Json::string(value)
          @provider.V4ToolResultJsonOutput(value~, ..) => value
          @provider.V4ToolResultErrorText(value~, ..) => Json::string(value)
          @provider.V4ToolResultErrorJson(value~, ..) => value
          _ => Json::string("execution denied")
        }
        encoded.push({
          "type": "tool-result",
          "toolCallId": result_part.tool_call_id,
          "toolName": result_part.tool_name,
          "output": { "type": output_type, "value": output_value },
        })
      }
      _ => ()
    }
  }
  Json::array(encoded)
}

///|
/// Serialize the full V4 call options into the gateway request body.
fn gateway_encode_options(
  options : @provider.LanguageModelV4CallOptions,
) -> Json raise {
  let fields : Map[String, Json] = Map([
    ("prompt", gateway_encode_prompt(options.prompt)),
  ])
  if options.tools.length() > 0 {
    let tools : Array[Json] = []
    for tool in options.tools {
      match tool {
        @provider.V4FunctionTool(definition) => {
          let function : Map[String, Json] = Map([
            ("name", Json::string(definition.name)),
          ])
          if definition.description is Some(value) {
            function["description"] = Json::string(value)
          }
          function["inputSchema"] = definition.input_schema
          tools.push({ "type": "function", "function": Json::object(function) })
        }
        @provider.V4ProviderTool(_) => ()
      }
    }
    if tools.length() > 0 {
      fields["tools"] = Json::array(tools)
    }
  }
  match options.tool_choice {
    Some(@provider.V4ToolChoiceAuto) => fields["toolChoice"] = "auto"
    Some(@provider.V4ToolChoiceNone) => fields["toolChoice"] = "none"
    Some(@provider.V4ToolChoiceRequired) => fields["toolChoice"] = "required"
    Some(@provider.V4ToolChoiceTool(name)) =>
      fields["toolChoice"] = { "type": "tool", "toolName": name }
    None => ()
  }
  if options.max_output_tokens is Some(value) {
    fields["maxOutputTokens"] = Json::number(value.to_double())
  }
  if options.temperature is Some(value) {
    fields["temperature"] = Json::number(value)
  }
  if options.top_p is Some(value) {
    fields["topP"] = Json::number(value)
  }
  if options.top_k is Some(value) {
    fields["topK"] = Json::number(value)
  }
  if options.frequency_penalty is Some(value) {
    fields["frequencyPenalty"] = Json::number(value)
  }
  if options.presence_penalty is Some(value) {
    fields["presencePenalty"] = Json::number(value)
  }
  if options.seed is Some(value) {
    fields["seed"] = Json::number(value.to_double())
  }
  if options.stop_sequences.length() > 0 {
    fields["stopSequences"] = Json::array(
      [
        for value in options.stop_sequences => Json::string(value)
      ],
    )
  }
  match options.response_format {
    @provider.V4ResponseJson(format) => {
      let response_format : Map[String, Json] = Map([
        ("type", Json::string("json")),
      ])
      if format.schema is Some(schema) {
        response_format["schema"] = schema
      }
      if format.name is Some(value) {
        response_format["name"] = Json::string(value)
      }
      if format.description is Some(value) {
        response_format["description"] = Json::string(value)
      }
      fields["responseFormat"] = Json::object(response_format)
    }
    _ => ()
  }
  match options.reasoning {
    @provider.V4ReasoningProviderDefault => ()
    @provider.V4ReasoningNone => fields["reasoning"] = "none"
    @provider.V4ReasoningMinimal => fields["reasoning"] = "minimal"
    @provider.V4ReasoningLow => fields["reasoning"] = "low"
    @provider.V4ReasoningMedium => fields["reasoning"] = "medium"
    @provider.V4ReasoningHigh => fields["reasoning"] = "high"
    @provider.V4ReasoningXHigh => fields["reasoning"] = "xhigh"
    @provider.V4ReasoningMax => fields["reasoning"] = "max"
  }
  if options.include_raw_chunks {
    fields["includeRawChunks"] = Json::boolean(true)
  }
  Json::object(fields)
}
