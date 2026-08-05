///|
/// One server-side sampling or compaction iteration reported by Anthropic.
pub(all) struct AnthropicUsageIteration {
  kind : String
  model : String?
  input_tokens : Int
  output_tokens : Int
  cache_creation_input_tokens : Int?
  cache_read_input_tokens : Int?
} derive(Debug, Eq)

///|
/// Details attached to a refusal stop reason.
pub(all) struct AnthropicStopDetails {
  kind : String
  category : String?
  explanation : String?
  recommended_model : String?
} derive(Debug, Eq)

///|
/// A skill loaded into an Anthropic container.
pub(all) struct AnthropicContainerSkillMetadata {
  kind : String
  skill_id : String
  version : String
} derive(Debug, Eq)

///|
/// Container information returned by code execution or another hosted tool.
pub(all) struct AnthropicContainerMetadata {
  expires_at : String?
  id : String
  skills : Array[AnthropicContainerSkillMetadata]?
} derive(Debug, Eq)

///|
/// One context-management edit applied by the server.
pub(all) struct AnthropicContextManagementEditMetadata {
  kind : String
  cleared_tool_uses : Int?
  cleared_input_tokens : Int?
  cleared_thinking_turns : Int?
} derive(Debug, Eq)

///|
/// Context-management changes applied to a request.
pub(all) struct AnthropicContextManagementMetadata {
  applied_edits : Array[AnthropicContextManagementEditMetadata]
} derive(Debug, Eq)

///|
/// Typed view of provider metadata returned by Anthropic Messages.
///
/// `raw` retains the original response object so newly introduced Anthropic
/// fields remain available before this view is extended.
pub(all) struct AnthropicMessageMetadata {
  usage : Json?
  stop_sequence : String?
  stop_details : AnthropicStopDetails?
  iterations : Array[AnthropicUsageIteration]?
  container : AnthropicContainerMetadata?
  context_management : AnthropicContextManagementMetadata?
  raw : Json
} derive(Debug)

///|
fn metadata_json_field(json : Json, names : Array[String]) -> Json? {
  match json {
    Object(fields) =>
      for name in names {
        match fields.get(name) {
          Some(value) => return Some(value)
          None => ()
        }
      }
    _ => ()
  }
  None
}

///|
fn metadata_string_field(json : Json, names : Array[String]) -> String? {
  match metadata_json_field(json, names) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn metadata_int_field(json : Json, names : Array[String]) -> Int? {
  match metadata_json_field(json, names) {
    Some(Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
fn parse_anthropic_usage_iteration(value : Json) -> AnthropicUsageIteration? {
  match value {
    Object(_) =>
      Some({
        kind: metadata_string_field(value, ["type"]).unwrap_or(""),
        model: metadata_string_field(value, ["model"]),
        input_tokens: metadata_int_field(value, ["input_tokens", "inputTokens"]).unwrap_or(
          0,
        ),
        output_tokens: metadata_int_field(value, [
          "output_tokens", "outputTokens",
        ]).unwrap_or(0),
        cache_creation_input_tokens: metadata_int_field(value, [
          "cache_creation_input_tokens", "cacheCreationInputTokens",
        ]),
        cache_read_input_tokens: metadata_int_field(value, [
          "cache_read_input_tokens", "cacheReadInputTokens",
        ]),
      })
    _ => None
  }
}

///|
fn parse_anthropic_iterations(value : Json) -> Array[AnthropicUsageIteration]? {
  match value {
    Array(values) => {
      let result : Array[AnthropicUsageIteration] = []
      for item in values {
        match parse_anthropic_usage_iteration(item) {
          Some(iteration) => result.push(iteration)
          None => ()
        }
      }
      Some(result)
    }
    Null => None
    _ => None
  }
}

///|
fn parse_anthropic_stop_details(value : Json) -> AnthropicStopDetails? {
  match value {
    Object(_) =>
      Some({
        kind: metadata_string_field(value, ["type"]).unwrap_or(""),
        category: metadata_string_field(value, ["category"]),
        explanation: metadata_string_field(value, ["explanation"]),
        recommended_model: metadata_string_field(value, [
          "recommended_model", "recommendedModel",
        ]),
      })
    _ => None
  }
}

///|
fn parse_anthropic_container_skill(
  value : Json,
) -> AnthropicContainerSkillMetadata? {
  match value {
    Object(_) =>
      Some({
        kind: metadata_string_field(value, ["type"]).unwrap_or(""),
        skill_id: metadata_string_field(value, ["skill_id", "skillId"]).unwrap_or(
          "",
        ),
        version: metadata_string_field(value, ["version"]).unwrap_or(""),
      })
    _ => None
  }
}

///|
fn parse_anthropic_container(value : Json) -> AnthropicContainerMetadata? {
  match value {
    Object(_) => {
      let skills = match metadata_json_field(value, ["skills"]) {
        Some(Array(values)) => {
          let parsed : Array[AnthropicContainerSkillMetadata] = []
          for item in values {
            match parse_anthropic_container_skill(item) {
              Some(skill) => parsed.push(skill)
              None => ()
            }
          }
          Some(parsed)
        }
        Some(Null) | None => None
        Some(_) => None
      }
      Some({
        expires_at: metadata_string_field(value, ["expires_at", "expiresAt"]),
        id: metadata_string_field(value, ["id"]).unwrap_or(""),
        skills,
      })
    }
    _ => None
  }
}

///|
fn parse_anthropic_context_edit(
  value : Json,
) -> AnthropicContextManagementEditMetadata? {
  match value {
    Object(_) =>
      Some({
        kind: metadata_string_field(value, ["type"]).unwrap_or(""),
        cleared_tool_uses: metadata_int_field(value, [
          "cleared_tool_uses", "clearedToolUses",
        ]),
        cleared_input_tokens: metadata_int_field(value, [
          "cleared_input_tokens", "clearedInputTokens",
        ]),
        cleared_thinking_turns: metadata_int_field(value, [
          "cleared_thinking_turns", "clearedThinkingTurns",
        ]),
      })
    _ => None
  }
}

///|
fn parse_anthropic_context_management(
  value : Json,
) -> AnthropicContextManagementMetadata? {
  match value {
    Object(_) => {
      let edits : Array[AnthropicContextManagementEditMetadata] = []
      match metadata_json_field(value, ["applied_edits", "appliedEdits"]) {
        Some(Array(values)) =>
          for item in values {
            match parse_anthropic_context_edit(item) {
              Some(edit) => edits.push(edit)
              None => ()
            }
          }
        _ => ()
      }
      Some({ applied_edits: edits })
    }
    _ => None
  }
}

///|
/// Parse a Messages response (or a `message` event wrapper) into typed
/// provider metadata. `None` means that the response contains no recognized
/// metadata fields.
pub fn decode_anthropic_message_metadata(
  json : Json,
) -> AnthropicMessageMetadata? {
  let source = match json {
    { "message": Object(message), .. } => Json::object(message)
    _ => json
  }
  let usage = metadata_json_field(source, ["usage"])
  let stop_sequence = metadata_string_field(source, [
    "stop_sequence", "stopSequence",
  ])
  let stop_details = match
    metadata_json_field(source, ["stop_details", "stopDetails"]) {
    Some(value) => parse_anthropic_stop_details(value)
    None => None
  }
  let iterations = match usage {
    Some(value) =>
      match metadata_json_field(value, ["iterations"]) {
        Some(value) => parse_anthropic_iterations(value)
        None =>
          match metadata_json_field(source, ["iterations"]) {
            Some(value) => parse_anthropic_iterations(value)
            None => None
          }
      }
    None =>
      match metadata_json_field(source, ["iterations"]) {
        Some(value) => parse_anthropic_iterations(value)
        None => None
      }
  }
  let container = match metadata_json_field(source, ["container"]) {
    Some(value) => parse_anthropic_container(value)
    None => None
  }
  let context_management = match
    metadata_json_field(source, ["context_management", "contextManagement"]) {
    Some(value) => parse_anthropic_context_management(value)
    None => None
  }
  if usage is None &&
    stop_sequence is None &&
    stop_details is None &&
    iterations is None &&
    container is None &&
    context_management is None {
    None
  } else {
    Some({
      usage,
      stop_sequence,
      stop_details,
      iterations,
      container,
      context_management,
      raw: source,
    })
  }
}

///|
/// AI SDK-style camel-case spelling for the typed metadata parser.
pub fn decodeAnthropicMessageMetadata(json : Json) -> AnthropicMessageMetadata? {
  decode_anthropic_message_metadata(json)
}
