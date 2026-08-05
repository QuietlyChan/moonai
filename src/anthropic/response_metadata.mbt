///|
/// Read the first present field from a JSON object. Anthropic occasionally
/// uses camel-case names in gateway responses, while the public API uses
/// snake_case.
fn anthropic_response_field(json : Json, names : Array[String]) -> Json? {
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
fn anthropic_copy_known_string(
  source : Map[String, Json],
  target : Map[String, Json],
  source_names : Array[String],
  target_name : String,
) -> Unit {
  for name in source_names {
    match source.get(name) {
      Some(String(value)) => {
        target[target_name] = Json::string(value)
        return
      }
      Some(Null) => {
        target[target_name] = Json::null()
        return
      }
      _ => ()
    }
  }
}

///|
fn anthropic_copy_known_json(
  source : Map[String, Json],
  target : Map[String, Json],
  source_names : Array[String],
  target_name : String,
) -> Unit {
  for name in source_names {
    match source.get(name) {
      Some(value) => {
        target[target_name] = value
        return
      }
      None => ()
    }
  }
}

///|
/// Map one usage iteration to the camel-case provider metadata shape used by
/// AI SDK. Unknown iteration entries are retained verbatim so newer API
/// variants remain inspectable.
fn anthropic_usage_iteration_metadata(value : Json) -> Json {
  match value {
    Object(fields) => {
      let mapped : Map[String, Json] = Map([])
      anthropic_copy_known_string(fields, mapped, ["type"], "type")
      anthropic_copy_known_string(fields, mapped, ["model"], "model")
      anthropic_copy_known_json(
        fields,
        mapped,
        ["input_tokens", "inputTokens"],
        "inputTokens",
      )
      anthropic_copy_known_json(
        fields,
        mapped,
        ["output_tokens", "outputTokens"],
        "outputTokens",
      )
      anthropic_copy_known_json(
        fields,
        mapped,
        ["cache_creation_input_tokens", "cacheCreationInputTokens"],
        "cacheCreationInputTokens",
      )
      anthropic_copy_known_json(
        fields,
        mapped,
        ["cache_read_input_tokens", "cacheReadInputTokens"],
        "cacheReadInputTokens",
      )
      Json::object(mapped)
    }
    _ => value
  }
}

///|
fn anthropic_iterations_metadata(value : Json) -> Json {
  match value {
    Array(values) =>
      Json::array(
        [
          for item in values => anthropic_usage_iteration_metadata(item)
        ],
      )
    _ => value
  }
}

///|
fn anthropic_stop_details_metadata(value : Json) -> Json {
  match value {
    Object(fields) => {
      let mapped : Map[String, Json] = Map([])
      anthropic_copy_known_string(fields, mapped, ["type"], "type")
      anthropic_copy_known_string(fields, mapped, ["category"], "category")
      anthropic_copy_known_string(
        fields,
        mapped,
        ["explanation"],
        "explanation",
      )
      anthropic_copy_known_string(
        fields,
        mapped,
        ["recommended_model", "recommendedModel"],
        "recommendedModel",
      )
      Json::object(mapped)
    }
    _ => value
  }
}

///|
fn anthropic_context_edit_metadata(value : Json) -> Json {
  match value {
    Object(fields) => {
      let mapped : Map[String, Json] = Map([])
      anthropic_copy_known_string(fields, mapped, ["type"], "type")
      anthropic_copy_known_json(
        fields,
        mapped,
        ["cleared_tool_uses", "clearedToolUses"],
        "clearedToolUses",
      )
      anthropic_copy_known_json(
        fields,
        mapped,
        ["cleared_input_tokens", "clearedInputTokens"],
        "clearedInputTokens",
      )
      anthropic_copy_known_json(
        fields,
        mapped,
        ["cleared_thinking_turns", "clearedThinkingTurns"],
        "clearedThinkingTurns",
      )
      Json::object(mapped)
    }
    _ => value
  }
}

///|
fn anthropic_context_management_metadata(value : Json) -> Json {
  match value {
    Object(_) => {
      let mapped : Map[String, Json] = Map([])
      match anthropic_response_field(value, ["applied_edits", "appliedEdits"]) {
        Some(Array(edits)) =>
          mapped["appliedEdits"] = Json::array(
            [
              for edit in edits => anthropic_context_edit_metadata(edit)
            ],
          )
        Some(other) => mapped["appliedEdits"] = other
        None => ()
      }
      Json::object(mapped)
    }
    _ => value
  }
}

///|
fn anthropic_container_metadata(value : Json) -> Json {
  match value {
    Object(fields) => {
      let mapped : Map[String, Json] = Map([])
      anthropic_copy_known_string(
        fields,
        mapped,
        ["expires_at", "expiresAt"],
        "expiresAt",
      )
      anthropic_copy_known_string(fields, mapped, ["id"], "id")
      match anthropic_response_field(value, ["skills"]) {
        Some(Array(skills)) => {
          let mapped_skills : Array[Json] = []
          for skill in skills {
            match skill {
              Object(skill_fields) => {
                let mapped_skill : Map[String, Json] = Map([])
                anthropic_copy_known_string(
                  skill_fields,
                  mapped_skill,
                  ["type"],
                  "type",
                )
                anthropic_copy_known_string(
                  skill_fields,
                  mapped_skill,
                  ["skill_id", "skillId"],
                  "skillId",
                )
                anthropic_copy_known_string(
                  skill_fields,
                  mapped_skill,
                  ["version"],
                  "version",
                )
                mapped_skills.push(Json::object(mapped_skill))
              }
              _ => mapped_skills.push(skill)
            }
          }
          mapped["skills"] = Json::array(mapped_skills)
        }
        Some(Null) => mapped["skills"] = Json::null()
        Some(other) => mapped["skills"] = other
        None => ()
      }
      Json::object(mapped)
    }
    _ => value
  }
}

///|
/// Return both the endpoint-qualified namespace and the base provider
/// namespace. The qualified key preserves Moonai's model identity, while the
/// base key matches AI SDK's `providerMetadata.anthropic` contract.
fn anthropic_metadata_map(
  provider_name : String,
  value : Json,
) -> Map[String, Json] {
  let endpoint_key = anthropic_metadata_key(provider_name)
  let base_key = if provider_name == "" {
    "anthropic"
  } else {
    let parts = [ for part in provider_name.split(".") => part ]
    if parts.length() > 0 && !parts[0].trim().is_empty() {
      parts[0].trim().to_owned()
    } else {
      "anthropic"
    }
  }
  let result : Map[String, Json] = Map([(endpoint_key, value)])
  if base_key != endpoint_key {
    result[base_key] = value
  }
  result
}

///|
/// Build the Anthropic-specific metadata emitted by a response or stream
/// event. The function intentionally only adds fields present in the event;
/// callers can merge successive events without losing earlier metadata.
fn anthropic_response_provider_metadata(
  json : Json,
  provider_name : String,
) -> Map[String, Json] {
  let source = match json {
    { "message": Object(message), .. } => Json::object(message)
    _ => json
  }
  let fields : Map[String, Json] = Map([])
  match anthropic_response_field(source, ["usage"]) {
    Some(usage) => {
      // Keep the raw snake-case object in `usage`; the normalized iteration
      // list is exposed as a sibling field, matching AI SDK metadata.
      fields["usage"] = usage
      match usage {
        Object(usage_fields) =>
          match usage_fields.get("iterations") {
            Some(iterations) =>
              fields["iterations"] = anthropic_iterations_metadata(iterations)
            None => ()
          }
        _ => ()
      }
    }
    None => ()
  }
  match anthropic_response_field(source, ["stop_sequence", "stopSequence"]) {
    Some(value) => fields["stopSequence"] = value
    None => ()
  }
  match anthropic_response_field(source, ["stop_details", "stopDetails"]) {
    Some(value) =>
      fields["stopDetails"] = anthropic_stop_details_metadata(value)
    None => ()
  }
  match anthropic_response_field(source, ["container"]) {
    Some(value) =>
      fields["container"] = match value {
        Null => Json::null()
        other => anthropic_container_metadata(other)
      }
    None => ()
  }
  match
    anthropic_response_field(source, ["context_management", "contextManagement"]) {
    Some(value) =>
      fields["contextManagement"] = match value {
        Null => Json::null()
        other => anthropic_context_management_metadata(other)
      }
    None => ()
  }
  if fields.length() == 0 {
    Map([])
  } else {
    anthropic_metadata_map(provider_name, Json::object(fields))
  }
}
