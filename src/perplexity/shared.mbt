///|
fn perplexity_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "error": { "type": String(kind), .. }, .. } => Some(kind)
    _ => None
  }
}

///|
fn perplexity_request_headers(
  api_key~ : String,
  headers~ : Map[String, String],
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    api_key,
    environment_variable_name="PERPLEXITY_API_KEY",
    description="Perplexity",
  )
  let base : Map[String, String] = Map([
    ("Content-Type", "application/json"),
    ("Authorization", "Bearer \{api_key}"),
  ])
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(base, headers),
      extra,
    ),
    ["ai-sdk/perplexity/\{VERSION}"],
  )
}

///|
/// Perplexity reports content filtering and context exhaustion under
/// OpenAI-style raw reasons.
fn perplexity_map_finish_reason(
  raw : String?,
) -> @provider.LanguageModelV4FinishReason {
  let unified = match raw {
    Some("stop") => @provider.V4FinishStop
    Some("length") => @provider.V4FinishLength
    Some("content_filter") => @provider.V4FinishContentFilter
    Some("tool_calls") => @provider.V4FinishToolCalls
    Some("error") => @provider.V4FinishError
    _ => @provider.V4FinishOther
  }
  { unified, raw, }
}

///|
/// Extract the response identity triple perplexity sends on every payload.
fn perplexity_response_metadata(value : Json) -> @provider.ResponseMetadata {
  let mut id : String? = None
  let mut model_id : String? = None
  let mut created_at : Int? = None
  if value is Object(fields) {
    match fields.get("id") {
      Some(String(text)) => id = Some(text)
      _ => ()
    }
    match fields.get("model") {
      Some(String(text)) => model_id = Some(text)
      _ => ()
    }
    match fields.get("created") {
      Some(Number(value, ..)) => created_at = Some(value.to_int())
      _ => ()
    }
  }
  { ..@provider.ResponseMetadata::empty(), id, model_id, created_at, }
}

///|
/// Pull the perplexity-specific usage/cost/images block into provider
/// metadata.
fn perplexity_provider_metadata(value : Json) -> Map[String, Json] {
  let metadata : Map[String, Json] = Map([])
  if value is Object(fields) {
    match fields.get("usage") {
      Some(Object(usage)) => {
        let summary : Map[String, Json] = Map([])
        if usage.get("citation_tokens") is Some(v) {
          summary["citationTokens"] = v
        } else {
          summary["citationTokens"] = Json::null()
        }
        if usage.get("num_search_queries") is Some(v) {
          summary["numSearchQueries"] = v
        } else {
          summary["numSearchQueries"] = Json::null()
        }
        metadata["usage"] = Json::object(summary)
        match usage.get("cost") {
          Some(Object(cost_fields)) => {
            let mapped : Map[String, Json] = Map([])
            let wire_to_meta : Array[(String, String)] = [
              ("input_tokens_cost", "inputTokensCost"),
              ("output_tokens_cost", "outputTokensCost"),
              ("reasoning_tokens_cost", "reasoningTokensCost"),
              ("request_cost", "requestCost"),
              ("citation_tokens_cost", "citationTokensCost"),
              ("search_queries_cost", "searchQueriesCost"),
              ("total_cost", "totalCost"),
            ]
            for entry in wire_to_meta {
              match cost_fields.get(entry.0) {
                Some(v) => mapped[entry.1] = v
                None => mapped[entry.1] = Json::null()
              }
            }
            metadata["cost"] = Json::object(mapped)
          }
          _ => metadata["cost"] = Json::null()
        }
      }
      _ => ()
    }
    match fields.get("images") {
      Some(Array(images)) => {
        let mapped : Array[Json] = []
        for image in images {
          if image is Object(image_fields) {
            let item : Map[String, Json] = Map([])
            for
              pair in [
                ("image_url", "imageUrl"),
                ("origin_url", "originUrl"),
                ("height", "height"),
                ("width", "width"),
              ] {
              if image_fields.get(pair.0) is Some(v) {
                item[pair.1] = v
              }
            }
            mapped.push(Json::object(item))
          }
        }
        metadata["images"] = Json::array(mapped)
      }
      _ => ()
    }
  }
  if metadata.length() > 0 {
    Map([("perplexity", Json::object(metadata))])
  } else {
    Map([])
  }
}

///|
fn perplexity_citations(value : Json) -> Array[String] {
  match value {
    { "citations": Array(urls), .. } => {
      let result : Array[String] = []
      for url in urls {
        if url is String(text) {
          result.push(text)
        }
      }
      result
    }
    _ => []
  }
}
