///|
priv struct AnthropicWireMessage {
  role : String
  content : Array[Json]
}

///|
fn text_content(text : String) -> Json {
  { "type": "text", "text": text }
}

///|
/// Read Anthropic content options from a provider-keyed options map.
fn anthropic_cache_control(
  options : Map[String, Json],
  provider_name : String,
) -> Json? {
  let values = resolve_anthropic_prompt_options(options, provider_name)
  match values.get("cacheControl") {
    Some(value) => Some(value)
    None => values.get("cache_control")
  }
}

///|
/// Resolve prompt-level Anthropic options using the same namespace rules as
/// call-level options. Message and content-part options may be attached to a
/// custom provider namespace (for example `localClaude`) or to `anthropic`.
fn resolve_anthropic_prompt_options(
  options : Map[String, Json],
  provider_name : String,
) -> Map[String, Json] {
  let resolution = @provider_utils.resolve_provider_options(
    options,
    provider_name~,
    aliases=["anthropic", "anthropic.messages"],
  )
  resolution.values
}

///|
/// Read a camel-case prompt option, accepting the wire spelling when decoded
/// provider metadata is replayed as a prompt.
fn anthropic_prompt_option(
  options : Map[String, Json],
  name : String,
  fallback_name : String,
) -> Json? {
  match options.get(name) {
    Some(value) => Some(value)
    None => options.get(fallback_name)
  }
}

///|
/// Return whether a file part asks Anthropic to place an uploaded file in the
/// code-execution container instead of sending it as a document/image block.
fn anthropic_container_upload(options : Map[String, Json]) -> Bool {
  match
    anthropic_prompt_option(options, "containerUpload", "container_upload") {
    Some(True) => true
    _ => false
  }
}

///|
/// Read document-specific metadata from a file part.
fn anthropic_document_option_string(
  options : Map[String, Json],
  name : String,
  fallback_name : String,
) -> String? {
  match anthropic_prompt_option(options, name, fallback_name) {
    Some(String(value)) if value != "" => Some(value)
    _ => None
  }
}

///|
/// Read the Anthropic document citation toggle from a file part.
fn anthropic_document_citations(options : Map[String, Json]) -> Json? {
  match anthropic_prompt_option(options, "citations", "citations") {
    Some(Object(fields)) if fields.get("enabled") is Some(True) =>
      Some({ "enabled": true })
    _ => None
  }
}

///|
/// Resolve the provider key used by Files API references. Provider model names
/// carry a modality suffix (`anthropic.messages`), while uploaded references
/// use the base provider name (`anthropic`).
fn anthropic_reference_provider_key(provider_name : String) -> String {
  let parts = [ for part in provider_name.split(".") => part ]
  if parts.length() > 0 && !parts[0].trim().is_empty() {
    parts[0].trim().to_owned()
  } else {
    "anthropic"
  }
}

///|
/// Resolve an Anthropic file reference, retaining the standard typed error when
/// neither the custom provider key nor `anthropic` is present.
fn resolve_anthropic_file_reference(
  reference : @provider.ProviderReference,
  provider_name : String,
) -> String raise @provider.NoSuchProviderReferenceError {
  let key = anthropic_reference_provider_key(provider_name)
  @provider_utils.resolve_provider_reference(reference, key) catch {
    _ => @provider_utils.resolve_provider_reference(reference, "anthropic")
  }
}

///|
/// Parse prompt-level tool changes into Anthropic content blocks.
fn anthropic_tool_changes(
  options : Map[String, Json],
  provider_name : String,
  warnings : Array[@provider.Warning],
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> Array[Json] {
  let scoped = resolve_anthropic_prompt_options(options, provider_name)
  let raw = match
    anthropic_prompt_option(scoped, "toolChanges", "tool_changes") {
    Some(Array(values)) => values
    Some(_) => {
      warnings.push(
        @provider.Warning::Compatibility(
          feature="providerOptions.anthropic.toolChanges",
          details="toolChanges must be an array; the value was ignored.",
        ),
      )
      []
    }
    None => []
  }
  let result : Array[Json] = []
  for item in raw {
    match item {
      Object(fields) => {
        let kind = match fields.get("type") {
          Some(String(value)) => value
          _ => ""
        }
        let name = match fields.get("toolName") {
          Some(String(value)) => value
          Some(_) => ""
          None =>
            match fields.get("tool_name") {
              Some(String(value)) => value
              Some(_) => ""
              _ => ""
            }
        }
        if (kind == "tool_addition" || kind == "tool_removal") && name != "" {
          result.push({
            "type": kind,
            "tool": {
              "type": "tool_reference",
              "name": tool_name_mapping.to_provider_tool_name(name),
            },
          })
        } else {
          warnings.push(
            @provider.Warning::Compatibility(
              feature="providerOptions.anthropic.toolChanges",
              details="Each tool change requires type tool_addition/tool_removal and a toolName; the invalid entry was ignored.",
            ),
          )
        }
      }
      _ =>
        warnings.push(
          @provider.Warning::Compatibility(
            feature="providerOptions.anthropic.toolChanges",
            details="Each tool change must be an object; the invalid entry was ignored.",
          ),
        )
    }
  }
  result
}

///|
/// Read a thinking signature from provider metadata attached to an assistant
/// message. The aliases cover both the public provider option spelling and
/// the metadata spelling emitted by the decoder.
fn anthropic_reasoning_signature(
  options : Map[String, Json],
  provider_name : String,
) -> String? {
  let values = resolve_anthropic_prompt_options(options, provider_name)
  for field in ["signature", "thinkingSignature", "thinking_signature"] {
    match values.get(field) {
      Some(String(value)) if value != "" => return Some(value)
      _ => ()
    }
  }
  None
}

///|
/// Add a provider-specific cache-control field to an Anthropic content block.
fn with_anthropic_cache_control(
  content : Json,
  options : Map[String, Json],
  provider_name : String,
) -> Json {
  match anthropic_cache_control(options, provider_name) {
    None => content
    Some(cache_control) =>
      match content {
        Object(fields) => {
          let result : Map[String, Json] = Map([])
          for entry in fields.iter2() {
            result[entry.0] = entry.1
          }
          result["cache_control"] = anthropic_wire_json(cache_control)
          Json::object(result)
        }
        _ => content
      }
  }
}

///|
/// Attach citation metadata to an assistant text block when it is being
/// replayed. Citation objects use the provider's snake_case wire spelling.
fn with_anthropic_citations(
  content : Json,
  options : Map[String, Json],
  provider_name : String,
) -> Json {
  let citations = resolve_anthropic_prompt_options(options, provider_name).get(
    "citations",
  )
  match citations {
    Some(value) =>
      match content {
        Object(fields) => {
          let result = @provider.copy_provider_metadata(fields)
          result["citations"] = anthropic_wire_json(value)
          Json::object(result)
        }
        _ => content
      }
    None => content
  }
}

///|
/// Apply a message-level cache policy only when a part did not provide one.
/// AI SDK applies message options to the final cacheable part of a message.
fn with_message_cache_control(
  content : Json,
  part_options : Map[String, Json],
  message_options : Map[String, Json],
  is_last_part : Bool,
  provider_name : String,
) -> Json {
  if is_last_part &&
    anthropic_cache_control(part_options, provider_name) is None {
    with_anthropic_cache_control(content, message_options, provider_name)
  } else {
    content
  }
}

///|
fn anthropic_document(
  source : Json,
  filename : String,
  provider_options : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = Map([
    ("type", Json::string("document")),
    ("source", source),
  ])
  let title = anthropic_document_option_string(
    provider_options, "title", "title",
  ).unwrap_or(filename)
  if title != "" {
    fields["title"] = Json::string(title)
  }
  match
    anthropic_document_option_string(provider_options, "context", "context") {
    Some(value) => fields["context"] = Json::string(value)
    None => ()
  }
  match anthropic_document_citations(provider_options) {
    Some(value) => fields["citations"] = value
    None => ()
  }
  Json::object(fields)
}

///|
fn AnthropicWireMessage::to_json(self : AnthropicWireMessage) -> Json {
  Json::object(
    Map([
      ("role", Json::string(self.role)),
      ("content", Json::array(self.content)),
    ]),
  )
}

///|
fn append_wire_message(
  messages : Array[AnthropicWireMessage],
  role : String,
  content : Array[Json],
) -> Unit {
  guard content.length() > 0 else { return }
  if messages.length() > 0 && messages[messages.length() - 1].role == role {
    let existing = messages[messages.length() - 1].content
    for part in content {
      existing.push(part)
    }
  } else {
    messages.push({ role, content })
  }
}

///|
fn tool_input(call : @provider.ToolCall) -> Json raise {
  if call.arguments.trim().is_empty() {
    return Json::empty_object()
  }
  let input = @json.parse(call.arguments) catch {
    error =>
      fail(
        "Anthropic tool call \{call.name} has invalid JSON arguments: \{error}",
      )
  }
  guard input is Object(_) else {
    fail("Anthropic tool call \{call.name} arguments must be a JSON object")
  }
  input
}

///|
fn user_content_part(
  part : @provider.LanguageModelContentPart,
  provider_name : String,
  beta_features : Array[String],
) -> Json raise {
  let provider_options = part.provider_options()
  let scoped_options = resolve_anthropic_prompt_options(
    provider_options, provider_name,
  )
  let content = match part.without_provider_options() {
    @provider.Text(value) => text_content(value)
    @provider.ImageUrl(url) =>
      { "type": "image", "source": { "type": "url", "url": url } }
    @provider.ImageData(data~, media_type~) =>
      {
        "type": "image",
        "source": {
          "type": "base64",
          "media_type": @provider_utils.resolve_full_media_type(
            media_type, data,
          ),
          "data": data,
        },
      }
    @provider.FileUrl(url~, media_type~, filename~) => {
      let top_level = @provider_utils.get_top_level_media_type(media_type)
      if top_level == "image" {
        { "type": "image", "source": { "type": "url", "url": url } }
      } else if media_type == "application/pdf" || media_type == "text/plain" {
        if media_type == "application/pdf" {
          append_unique_beta(beta_features, "pdfs-2024-09-25")
        }
        anthropic_document(
          { "type": "url", "url": url },
          filename,
          scoped_options,
        )
      } else {
        fail("Anthropic Messages does not accept file media type \{media_type}")
      }
    }
    @provider.FileData(data~, media_type~, filename~) => {
      let top_level = @provider_utils.get_top_level_media_type(media_type)
      let full_media_type = @provider_utils.resolve_full_media_type(
        media_type, data,
      )
      if top_level == "image" {
        {
          "type": "image",
          "source": {
            "type": "base64",
            "media_type": full_media_type,
            "data": data,
          },
        }
      } else if full_media_type == "application/pdf" {
        append_unique_beta(beta_features, "pdfs-2024-09-25")
        anthropic_document(
          { "type": "base64", "media_type": "application/pdf", "data": data },
          filename,
          scoped_options,
        )
      } else if media_type == "text/plain" {
        anthropic_document(
          {
            "type": "text",
            "media_type": "text/plain",
            "data": @provider_utils.decode_base64_text(data),
          },
          filename,
          scoped_options,
        )
      } else {
        fail(
          "Anthropic Messages does not accept file media type \{full_media_type}",
        )
      }
    }
    @provider.FileReference(reference~, media_type~, filename~) => {
      let file_id = resolve_anthropic_file_reference(reference, provider_name)
      append_unique_beta(beta_features, "files-api-2025-04-14")
      if anthropic_container_upload(scoped_options) {
        { "type": "container_upload", "file_id": file_id }
      } else {
        let top_level = @provider_utils.get_top_level_media_type(media_type)
        if top_level == "image" {
          { "type": "image", "source": { "type": "file", "file_id": file_id } }
        } else if media_type == "application/pdf" || media_type == "text/plain" {
          if media_type == "application/pdf" {
            append_unique_beta(beta_features, "pdfs-2024-09-25")
          }
          anthropic_document(
            { "type": "file", "file_id": file_id },
            filename,
            scoped_options,
          )
        } else {
          fail(
            "Anthropic Messages does not accept file media type \{media_type}",
          )
        }
      }
    }
    @provider.AudioData(..) =>
      fail("Anthropic Messages does not accept audio content parts")
    @provider.Reasoning(_)
    | @provider.ReasoningFileUrl(..)
    | @provider.ReasoningFileData(..)
    | @provider.Custom(..)
    | @provider.ToolCallPart(_)
    | @provider.ToolResultPart(_)
    | @provider.ToolApprovalRequestPart(_)
    | @provider.ToolApprovalResponsePart(_) =>
      fail(
        "Anthropic Messages does not accept this content part in a user message",
      )
    @provider.ProviderOptions(part~, ..) =>
      user_content_part(part, provider_name, beta_features)
  }
  with_anthropic_cache_control(content, provider_options, provider_name)
}

///|
fn anthropic_tool_result_content_part(
  part : @provider.LanguageModelToolResultContentPart,
  provider_name : String,
  beta_features : Array[String],
) -> Json raise {
  match part {
    @provider.LanguageModelToolText(text~, provider_options~) =>
      with_anthropic_cache_control(
        text_content(text),
        provider_options,
        provider_name,
      )
    @provider.LanguageModelToolFileUrl(
      url~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      user_content_part(
        @provider.LanguageModelContentPart::file_url(
          url~,
          media_type~,
          filename~,
        ).with_provider_options(provider_options),
        provider_name,
        beta_features,
      )
    @provider.LanguageModelToolFileData(
      data~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      user_content_part(
        @provider.LanguageModelContentPart::file_data(
          data~,
          media_type~,
          filename~,
        ).with_provider_options(provider_options),
        provider_name,
        beta_features,
      )
    @provider.LanguageModelToolFileReference(
      reference~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      user_content_part(
        @provider.LanguageModelContentPart::file_reference(
          reference~,
          media_type~,
          filename~,
        ).with_provider_options(provider_options),
        provider_name,
        beta_features,
      )
    @provider.LanguageModelToolCustom(..) =>
      fail("Anthropic tool result content does not accept custom parts")
  }
}

///|
fn anthropic_tool_result_output_content(
  output : @provider.LanguageModelToolResultOutput,
  provider_name : String,
  beta_features : Array[String],
) -> Array[Json] raise {
  match output {
    @provider.LanguageModelToolTextOutput(value~, ..)
    | @provider.LanguageModelToolErrorText(value~, ..) => [text_content(value)]
    @provider.LanguageModelToolJsonOutput(..)
    | @provider.LanguageModelToolErrorJson(..)
    | @provider.LanguageModelToolExecutionDenied(..) =>
      [text_content(output.to_json().stringify())]
    @provider.LanguageModelToolContent(value~, ..) =>
      [
        for part in value => {
          anthropic_tool_result_content_part(part, provider_name, beta_features)
        }
      ]
  }
}

///|
fn anthropic_tool_result_to_json(
  result : @provider.LanguageModelToolResult,
  provider_name : String,
  beta_features : Array[String],
) -> Json raise {
  Json::object(
    Map([
      ("type", Json::string("tool_result")),
      ("tool_use_id", Json::string(result.tool_call_id)),
      (
        "content",
        Json::array(
          anthropic_tool_result_output_content(
            result.output,
            provider_name,
            beta_features,
          ),
        ),
      ),
    ]),
  )
}

///|
fn tool_choice_to_json(
  choice : @provider.ToolChoice,
  disable_parallel_tool_use : Bool?,
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> Json {
  let fields : Map[String, Json] = match choice {
    @provider.Auto => Map([("type", Json::string("auto"))])
    @provider.Required => Map([("type", Json::string("any"))])
    @provider.Named(name) =>
      Map([
        ("type", Json::string("tool")),
        ("name", Json::string(tool_name_mapping.to_provider_tool_name(name))),
      ])
    @provider.NoTool => Map([("type", Json::string("auto"))])
  }
  if disable_parallel_tool_use is Some(value) {
    fields["disable_parallel_tool_use"] = Json::boolean(value)
  }
  Json::object(fields)
}

///|
fn normalized_temperature(value : Double) -> Double {
  if value > 1.0 {
    1.0
  } else if value < 0.0 {
    0.0
  } else {
    value
  }
}

///|
fn camel_to_snake(value : String) -> String {
  let result = StringBuilder::new(size_hint=value.length() + 4)
  for character in value {
    if character.is_ascii_uppercase() {
      result.write_char('_')
      result.write_char(character.to_ascii_lowercase())
    } else {
      result.write_char(character)
    }
  }
  result.to_string()
}

///|
fn anthropic_wire_json(value : Json) -> Json {
  match value {
    Object(fields) => {
      let mapped : Map[String, Json] = Map([])
      for entry in fields.iter2() {
        let (key, item) = entry
        mapped[camel_to_snake(key)] = anthropic_wire_json(item)
      }
      Json::object(mapped)
    }
    Array(values) =>
      Json::array([ for item in values => anthropic_wire_json(item) ])
    other => other
  }
}

///|
fn anthropic_required_container_string(
  fields : Map[String, Json],
  camel_name : String,
  wire_name : String,
  description : String,
) -> String raise {
  match anthropic_prompt_option(fields, camel_name, wire_name) {
    Some(String(value)) => value
    _ =>
      fail("Anthropic container skill requires string field '\{description}'")
  }
}

///|
fn anthropic_optional_container_string(
  fields : Map[String, Json],
  camel_name : String,
  wire_name : String,
) -> String? raise {
  match anthropic_prompt_option(fields, camel_name, wire_name) {
    Some(String(value)) => Some(value)
    Some(_) =>
      fail("Anthropic container field '\{camel_name}' must be a string")
    None => None
  }
}

///|
fn anthropic_provider_reference_from_json(
  value : Json,
) -> @provider.ProviderReference raise {
  guard value is Object(fields) else {
    fail("Anthropic custom skill providerReference must be an object")
  }
  let entries : Map[String, String] = Map([])
  for entry in fields.iter2() {
    let (provider_name, provider_id) = entry
    match provider_id {
      String(id) => entries[provider_name] = id
      _ =>
        fail("Anthropic custom skill providerReference values must be strings")
    }
  }
  @provider.ProviderReference::new(entries)
}

///|
fn anthropic_container_skill_wire_json(value : Json) -> Json raise {
  guard value is Object(fields) else {
    fail("Anthropic container skills must be objects")
  }
  let kind = anthropic_required_container_string(fields, "type", "type", "type")
  let skill_id = match anthropic_prompt_option(fields, "skillId", "skill_id") {
    Some(String(value)) => value
    Some(_) => fail("Anthropic container skill skillId must be a string")
    None if kind == "custom" => {
      guard anthropic_prompt_option(
          fields, "providerReference", "provider_reference",
        )
        is Some(reference) else {
        fail("Anthropic custom skill requires providerReference")
      }
      @provider_utils.resolve_provider_reference(
        anthropic_provider_reference_from_json(reference),
        "anthropic",
      )
    }
    None => fail("Anthropic built-in skill requires skillId")
  }
  guard kind == "anthropic" || kind == "custom" else {
    fail("Unsupported Anthropic container skill type '\{kind}'")
  }
  let version = anthropic_optional_container_string(
    fields, "version", "version",
  )
  Json::object(
    Map(
      [
        ("type", Json::string(kind)),
        ("skill_id", Json::string(skill_id)),
        ..if version is Some(value) {
          [("version", Json::string(value))]
        },
      ],
    ),
  )
}

///|
fn anthropic_container_wire_json(value : Json) -> Json? raise {
  guard value is Object(fields) else {
    fail("Anthropic container options must be an object")
  }
  match fields.get("skills") {
    Some(Array(skills)) if skills.length() > 0 => {
      let output : Map[String, Json] = Map([])
      if fields.get("id") is Some(String(id)) {
        output["id"] = Json::string(id)
      } else if fields.get("id") is Some(_) {
        fail("Anthropic container id must be a string")
      }
      output["skills"] = Json::array(
        [
          for skill in skills => anthropic_container_skill_wire_json(skill)
        ],
      )
      Some(Json::object(output))
    }
    Some(Array(_)) | None =>
      match fields.get("id") {
        Some(String(id)) => Some(Json::string(id))
        Some(_) => fail("Anthropic container id must be a string")
        None => None
      }
    Some(_) => fail("Anthropic container skills must be an array")
  }
}

///|
fn anthropic_container_has_skills(value : Json?) -> Bool {
  match value {
    Some(Object(fields)) =>
      match fields.get("skills") {
        Some(Array(skills)) => skills.length() > 0
        _ => false
      }
    _ => false
  }
}

///|
fn has_anthropic_skills_code_execution_tool(
  tools : Array[@provider.ToolDefinition],
) -> Bool {
  tools.any(fn(tool) {
    match tool {
      @provider.ProviderTool(id~, ..) =>
        id == "anthropic.code_execution_20250825" ||
        id == "anthropic.code_execution_20260120"
      _ => false
    }
  })
}

///|
fn thinking_to_json(thinking : AnthropicThinking) -> Json {
  match thinking {
    AnthropicThinkingAdaptive(display) =>
      Json::object(
        Map(
          [
            ("type", Json::string("adaptive")),
            ..if display is Some(value) {
              [("display", Json::string(value.wire_name()))]
            },
          ],
        ),
      )
    AnthropicThinkingEnabled(budget_tokens) =>
      Json::object(
        Map(
          [
            ("type", Json::string("enabled")),
            ..if budget_tokens is Some(value) {
              [("budget_tokens", Json::number(value.to_double()))]
            },
          ],
        ),
      )
    AnthropicThinkingDisabled => { "type": "disabled" }
  }
}

///|
fn append_unique_beta(values : Array[String], value : String) -> Unit {
  for existing in values {
    if existing == value {
      return
    }
  }
  values.push(value)
}

///|
fn is_nonempty_fallback(value : Json) -> Bool {
  match value {
    String("default") => true
    Array(values) => values.length() > 0
    _ => false
  }
}

///|
fn prepare_anthropic_v4_request(
  model_id : String,
  options : @provider.LanguageModelV4CallOptions,
  provider_name : String,
  stream : Bool,
) -> AnthropicPreparedRequest raise {
  let parsed = parse_anthropic_options(options.provider_options, provider_name)
  let provider_options = parsed.options
  let warnings = parsed.warnings.copy()
  let tool_name_mapping = create_anthropic_tool_name_mapping(options.tools)
  let capabilities = get_anthropic_model_capabilities(model_id)
  let prompt = convert_v4_prompt_to_anthropic(
    options.prompt,
    provider_name,
    provider_options.send_reasoning,
    tool_name_mapping,
  )
  for warning in prompt.warnings {
    warnings.push(warning)
  }
  let mut thinking = provider_options.thinking
  let mut effort = provider_options.effort
  if !(options.reasoning_effort is @provider.ProviderDefault) && effort is None {
    let (mapped_thinking, mapped_effort) = map_anthropic_reasoning(
      options.reasoning_effort,
      capabilities,
      warnings,
    )
    if thinking is None {
      thinking = mapped_thinking
    }
    if mapped_effort is Some(value) &&
      !(thinking is Some(AnthropicThinkingDisabled)) {
      effort = Some(value)
    }
  }
  if capabilities.rejects_thinking_disabled_above_high &&
    thinking is Some(AnthropicThinkingDisabled) &&
    (effort == Some("xhigh") || effort == Some("max")) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="providerOptions.anthropic.effort",
        details="This model does not support xhigh or max effort when thinking is disabled; effort was lowered to high.",
      ),
    )
    effort = Some("high")
  }
  let mut thinking_budget : Int? = match thinking {
    Some(AnthropicThinkingEnabled(value)) => value
    _ => None
  }
  if thinking is Some(AnthropicThinkingEnabled(None)) {
    warnings.push(
      @provider.Warning::Compatibility(
        feature="extended thinking",
        details="thinking budget is required when thinking is enabled; using 1024 tokens.",
      ),
    )
    thinking_budget = Some(1024)
    thinking = Some(AnthropicThinkingEnabled(Some(1024)))
  }
  let thinking_enabled = match thinking {
    Some(AnthropicThinkingAdaptive(_)) | Some(AnthropicThinkingEnabled(_)) =>
      true
    _ => false
  }
  let mut temperature = options.temperature.map(normalized_temperature)
  let mut top_p = options.top_p
  let mut top_k = options.top_k
  if options.frequency_penalty is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="frequencyPenalty",
        details="Anthropic Messages does not define a frequency penalty field.",
      ),
    )
  }
  if options.presence_penalty is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="presencePenalty",
        details="Anthropic Messages does not define a presence penalty field.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="seed",
        details="Anthropic Messages does not define a seed field.",
      ),
    )
  }
  match options.temperature {
    Some(value) if value > 1.0 =>
      warnings.push(
        @provider.Warning::Unsupported(
          feature="temperature",
          details="temperature exceeds Anthropic maximum of 1.0 and is clamped to 1.0.",
        ),
      )
    Some(value) if value < 0.0 =>
      warnings.push(
        @provider.Warning::Unsupported(
          feature="temperature",
          details="temperature is below Anthropic minimum of 0.0 and is clamped to 0.0.",
        ),
      )
    _ => ()
  }
  if capabilities.rejects_sampling_parameters || thinking_enabled {
    if temperature is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="temperature",
          details=if thinking_enabled {
            "temperature is not supported when thinking is enabled and was ignored."
          } else {
            "temperature is not supported by this model and was ignored."
          },
        ),
      )
      temperature = None
    }
    if top_p is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="topP",
          details=if thinking_enabled {
            "topP is not supported when thinking is enabled and was ignored."
          } else {
            "topP is not supported by this model and was ignored."
          },
        ),
      )
      top_p = None
    }
    if top_k is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="topK",
          details=if thinking_enabled {
            "topK is not supported when thinking is enabled and was ignored."
          } else {
            "topK is not supported by this model and was ignored."
          },
        ),
      )
      top_k = None
    }
  } else if model_id.contains("claude-") &&
    temperature is Some(_) &&
    top_p is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="topP",
        details="Anthropic models do not support topP together with temperature; topP was ignored.",
      ),
    )
    top_p = None
  }
  if options.response_format is @provider.JsonResponse({ schema: None, .. }) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="responseFormat",
        details="Anthropic JSON response format requires an explicit schema and is ignored.",
      ),
    )
  }
  if !capabilities.is_known_model && options.max_output_tokens is None {
    warnings.push(
      @provider.Warning::Compatibility(
        feature="maxOutputTokens",
        details="The model '\{model_id}' is unknown; max output tokens defaulted to \{capabilities.max_output_tokens}.",
      ),
    )
  }
  let requested_max_tokens = options.max_output_tokens.unwrap_or(
    capabilities.max_output_tokens,
  )
  let mut max_tokens = requested_max_tokens + thinking_budget.unwrap_or(0)
  if capabilities.is_known_model && max_tokens > capabilities.max_output_tokens {
    if options.max_output_tokens is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="maxOutputTokens",
          details="maxOutputTokens plus thinking budget exceeds this model's limit and was clamped.",
        ),
      )
    }
    max_tokens = capabilities.max_output_tokens
  }
  let native_structured_output = match options.response_format {
    @provider.JsonResponse({ schema: Some(_), .. }) =>
      provider_options.structured_output_mode == "outputFormat" ||
      (
        provider_options.structured_output_mode == "auto" &&
        capabilities.supports_structured_output
      )
    _ => false
  }
  let json_tool = match options.response_format {
    @provider.JsonResponse({ schema: Some(schema), .. }) if !native_structured_output =>
      Some(
        @provider.ToolDefinition::new(
          "json",
          schema,
          description="Respond with a JSON object.",
        ),
      )
    _ => None
  }
  // Beta features are collected by prompt conversion as well as tool and
  // request option preparation, so keep one mutable set for the whole pass.
  let prepared_beta_features = provider_options.beta_features.copy()
  for feature in prompt.beta_features {
    append_unique_beta(prepared_beta_features, feature)
  }
  let system = prompt.system
  let messages = prompt.messages
  let tools_disabled = match options.tool_choice {
    Some(@provider.NoTool) => true
    _ => false
  }
  let include_tools = (options.tools.length() > 0 || json_tool is Some(_)) &&
    !(tools_disabled && json_tool is None)
  let eager_input_streaming = stream && provider_options.tool_streaming
  let requested_tools = options.tools.copy()
  if include_tools && json_tool is Some(tool) {
    requested_tools.push(tool)
  }
  let prepared_tools = prepare_anthropic_tools(
    if include_tools {
      requested_tools
    } else {
      []
    },
    capabilities.supports_structured_output,
    capabilities.supports_structured_output,
    eager_input_streaming,
    warnings,
  )
  let tools = prepared_tools.tools
  let output_config : Map[String, Json] = Map([])
  if effort is Some(value) {
    output_config["effort"] = Json::string(value)
  }
  if provider_options.task_budget is Some(value) {
    output_config["task_budget"] = anthropic_wire_json(value)
  }
  match options.response_format {
    @provider.JsonResponse({ schema: Some(schema), .. }) if native_structured_output =>
      output_config["format"] = {
        "type": "json_schema",
        "schema": sanitize_json_schema(schema),
      }
    _ => ()
  }
  let container = match provider_options.container {
    Some(value) => anthropic_container_wire_json(value)
    None => None
  }
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      (
        "messages",
        Json::array([ for message in messages => message.to_json() ]),
      ),
      ("max_tokens", Json::number(max_tokens.to_double())),
      ..if stream {
        [("stream", Json::boolean(true))]
      },
      ..if system.length() > 0 {
        [("system", Json::array(system))]
      },
      ..if temperature is Some(value) {
        [("temperature", Json::number(value))]
      },
      ..if top_p is Some(value) {
        [("top_p", Json::number(value))]
      },
      ..if top_k is Some(value) {
        [("top_k", Json::number(value))]
      },
      ..if options.stop_sequences.length() > 0 {
        [
          (
            "stop_sequences",
            Json::array(
              [
                for stop in options.stop_sequences => Json::string(stop)
              ],
            ),
          ),
        ]
      },
      ..if thinking is Some(value) {
        [("thinking", thinking_to_json(value))]
      },
      ..if output_config.length() > 0 {
        [("output_config", Json::object(output_config))]
      },
      ..if provider_options.cache_control is Some(value) {
        [("cache_control", anthropic_wire_json(value))]
      },
      ..if provider_options.metadata_user_id is Some(value) {
        [("metadata", ({ "user_id": value } : Json))]
      },
      ..if provider_options.mcp_servers.length() > 0 {
        [
          (
            "mcp_servers",
            anthropic_wire_json(Json::array(provider_options.mcp_servers)),
          ),
        ]
      },
      ..if container is Some(value) {
        [("container", value)]
      },
      ..if provider_options.speed is Some(value) {
        [("speed", Json::string(value))]
      },
      ..if provider_options.inference_geo is Some(value) {
        [("inference_geo", Json::string(value))]
      },
      ..if provider_options.fallbacks is Some(value) &&
        is_nonempty_fallback(value) {
        [("fallbacks", value)]
      },
      ..if provider_options.context_management is Some(value) {
        [("context_management", anthropic_wire_json(value))]
      },
    ],
  )
  if include_tools {
    fields["tools"] = Json::array(tools)
    match json_tool {
      Some(_) =>
        fields["tool_choice"] = tool_choice_to_json(
          @provider.Required,
          Some(true),
          tool_name_mapping,
        )
      None =>
        match options.tool_choice {
          Some(choice) =>
            fields["tool_choice"] = tool_choice_to_json(
              choice,
              provider_options.disable_parallel_tool_use,
              tool_name_mapping,
            )
          None =>
            match provider_options.disable_parallel_tool_use {
              Some(true) =>
                fields["tool_choice"] = tool_choice_to_json(
                  @provider.Auto,
                  Some(true),
                  tool_name_mapping,
                )
              _ => ()
            }
        }
    }
  }
  for feature in prepared_tools.beta_features {
    append_unique_beta(prepared_beta_features, feature)
  }
  if native_structured_output ||
    (
      capabilities.supports_structured_output &&
      options.tools.any(tool => tool.strict())
    ) {
    append_unique_beta(prepared_beta_features, "structured-outputs-2025-11-13")
  }
  if provider_options.mcp_servers.length() > 0 {
    append_unique_beta(prepared_beta_features, "mcp-client-2025-04-04")
  }
  if provider_options.context_management is Some(value) {
    append_unique_beta(prepared_beta_features, "context-management-2025-06-27")
    if value.stringify().contains("compact_20260112") {
      append_unique_beta(prepared_beta_features, "compact-2026-01-12")
    }
  }
  if anthropic_container_has_skills(provider_options.container) {
    append_unique_beta(prepared_beta_features, "code-execution-2025-08-25")
    append_unique_beta(prepared_beta_features, "skills-2025-10-02")
    append_unique_beta(prepared_beta_features, "files-api-2025-04-14")
    if !has_anthropic_skills_code_execution_tool(options.tools) {
      warnings.push(
        @provider.Warning::Other(
          message="code execution tool is required when using skills",
        ),
      )
    }
  }
  if provider_options.task_budget is Some(_) {
    append_unique_beta(prepared_beta_features, "task-budgets-2026-03-13")
  }
  if provider_options.speed == Some("fast") {
    append_unique_beta(prepared_beta_features, "fast-mode-2026-02-01")
  }
  match provider_options.fallbacks {
    Some(String("default")) =>
      append_unique_beta(
        prepared_beta_features, "server-side-fallback-2026-07-01",
      )
    Some(Array(values)) if values.length() > 0 =>
      append_unique_beta(
        prepared_beta_features, "server-side-fallback-2026-06-01",
      )
    _ => ()
  }
  {
    body: Json::object(fields),
    warnings,
    beta_features: prepared_beta_features,
    tool_name_mapping,
  }
}

///|
/// Temporary inward-facing migration adapter. The Anthropic request core is
/// V4-native; remaining ChatModel callers can only move in this direction.
fn anthropic_v4_options_from_chat(
  options : @provider.ChatCallOptions,
) -> @provider.LanguageModelV4CallOptions {
  @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::from_language_model_prompt(
      options.messages,
    ),
    tools=options.tools,
    tool_choice?=options.tool_choice,
    response_format=options.response_format,
    reasoning_effort=options.reasoning_effort,
    max_output_tokens?=options.max_output_tokens,
    temperature?=options.temperature,
    top_p?=options.top_p,
    top_k?=options.top_k,
    frequency_penalty?=options.frequency_penalty,
    presence_penalty?=options.presence_penalty,
    seed?=options.seed,
    stop_sequences=options.stop_sequences,
    include_raw_chunks=options.include_raw_chunks,
    headers=options.headers,
    provider_options=options.provider_options,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}

///|
fn prepare_anthropic_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  provider_name : String,
  stream : Bool,
) -> AnthropicPreparedRequest raise {
  prepare_anthropic_v4_request(
    model_id,
    anthropic_v4_options_from_chat(options),
    provider_name,
    stream,
  )
}

///|
/// Encode V4 call options as an Anthropic Messages request.
pub fn encode_messages_v4_request(
  model_id : String,
  options : @provider.LanguageModelV4CallOptions,
  provider_name? : String = "",
  stream? : Bool = true,
) -> Json raise {
  prepare_anthropic_v4_request(model_id, options, provider_name, stream).body
}

///|
/// Encode normalized call options as an Anthropic Messages request.
pub fn encode_messages_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  provider_name? : String = "",
  stream? : Bool = true,
) -> Json raise {
  prepare_anthropic_request(model_id, options, provider_name, stream).body
}
