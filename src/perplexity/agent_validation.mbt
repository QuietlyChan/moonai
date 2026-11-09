///|
fn perplexity_agent_search_result_schema() -> Json {
  {
    "type": "object",
    "required": ["title", "url"],
    "properties": {
      "id": { "type": "number" },
      "title": { "type": "string" },
      "url": { "type": "string" },
      "snippet": { "type": "string" },
      "date": { "type": ["string", "null"] },
      "last_updated": { "type": ["string", "null"] },
      "source": { "type": "string" },
    },
  }
}

///|
fn perplexity_agent_fetch_result_schema() -> Json {
  {
    "type": "object",
    "required": ["title", "url"],
    "properties": {
      "title": { "type": "string" },
      "url": { "type": "string" },
      "snippet": { "type": "string" },
    },
  }
}

///|
fn perplexity_agent_output_item_validation_error(item : Json) -> String? {
  guard item is { "type": String(kind), .. } else {
    return Some("output item must be an object with a string type")
  }
  let schema : Json = match kind {
    "message" =>
      {
        "properties": {
          "id": { "type": ["string", "null"] },
          "content": {
            "type": ["array", "null"],
            "items": {
              "type": "object",
              "required": ["type"],
              "properties": {
                "type": { "type": "string" },
                "text": { "type": "string" },
                "annotations": {
                  "type": ["array", "null"],
                  "items": {
                    "type": "object",
                    "properties": {
                      "type": { "type": "string" },
                      "url": { "type": "string" },
                      "title": { "type": "string" },
                    },
                  },
                },
              },
            },
          },
        },
      }
    "search_results" =>
      {
        "properties": {
          "queries": {
            "type": ["array", "null"],
            "items": { "type": "string" },
          },
          "results": {
            "type": ["array", "null"],
            "items": perplexity_agent_search_result_schema(),
          },
        },
      }
    "fetch_url_results" =>
      {
        "properties": {
          "contents": {
            "type": ["array", "null"],
            "items": perplexity_agent_fetch_result_schema(),
          },
        },
      }
    "function_call" =>
      {
        "properties": {
          "id": { "type": ["string", "null"] },
          "call_id": { "type": ["string", "null"] },
          "name": { "type": ["string", "null"] },
          "arguments": { "type": ["string", "null"] },
          "thought_signature": { "type": ["string", "null"] },
        },
      }
    // Native traces have unrelated shapes and remain available in raw output.
    _ => return None
  }
  if @provider_utils.json_schema_matches(schema, item) {
    None
  } else {
    Some("malformed " + kind + " output item")
  }
}

///|
fn perplexity_agent_response_validation_error(value : Json) -> String? {
  let schema : Json = {
    "type": "object",
    "required": ["status", "output"],
    "properties": {
      "id": { "type": ["string", "null"] },
      "model": { "type": ["string", "null"] },
      "created_at": { "type": ["number", "null"] },
      "status": { "type": "string" },
      "output": { "type": "array" },
      "usage": {
        "type": ["object", "null"],
        "properties": {
          "input_tokens": { "type": "number" },
          "output_tokens": { "type": "number" },
          "total_tokens": { "type": "number" },
          "input_tokens_details": {
            "type": ["object", "null"],
            "properties": {
              "cached_tokens": { "type": "number" },
              "cache_creation_input_tokens": { "type": "number" },
              "cache_read_input_tokens": { "type": "number" },
            },
          },
          "output_tokens_details": {
            "type": ["object", "null"],
            "properties": { "reasoning_tokens": { "type": "number" } },
          },
          "cost": { "type": ["object", "null"] },
          "tool_calls_details": { "type": ["object", "null"] },
        },
      },
    },
  }
  if !@provider_utils.json_schema_matches(schema, value) {
    return Some(
      "response must contain status and an output array with valid metadata and usage",
    )
  }
  if value is { "output": Array(items), .. } {
    for item in items {
      if perplexity_agent_output_item_validation_error(item) is Some(error) {
        return Some(error)
      }
    }
  }
  None
}

///|
fn perplexity_agent_chunk_validation_error(value : Json) -> String? {
  let schema : Json = {
    "type": "object",
    "required": ["type"],
    "properties": {
      "type": { "type": "string" },
      "delta": { "type": ["string", "null"] },
      "text": { "type": ["string", "null"] },
      "thought": { "type": ["string", "null"] },
      "item_id": { "type": ["string", "null"] },
      "sequence_number": { "type": ["number", "null"] },
      "output_index": { "type": ["number", "null"] },
      "content_index": { "type": ["number", "null"] },
      "queries": { "type": ["array", "null"], "items": { "type": "string" } },
      "results": {
        "type": ["array", "null"],
        "items": perplexity_agent_search_result_schema(),
      },
      "contents": {
        "type": ["array", "null"],
        "items": perplexity_agent_fetch_result_schema(),
      },
    },
  }
  if !@provider_utils.json_schema_matches(schema, value) {
    return Some("stream chunk has invalid fields or no string type")
  }
  match value {
    { "item": Null, .. } => ()
    { "item": item, .. } =>
      if perplexity_agent_output_item_validation_error(item) is Some(error) {
        return Some(error)
      }
    _ => ()
  }
  match value {
    {
      "type": "response.completed"
      | "response.incomplete",
      "response": Object(_) as response,
      ..
    } => perplexity_agent_response_validation_error(response)
    _ => None
  }
}
