///|
fn cohere_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn cohere_request_headers(
  api_key~ : String,
  headers~ : Map[String, String],
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    api_key,
    environment_variable_name="COHERE_API_KEY",
    description="Cohere",
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
    ["ai-sdk/cohere/\{VERSION}"],
  )
}

///|
fn cohere_map_finish_reason(
  raw : String?,
) -> @provider.LanguageModelV4FinishReason {
  let unified = match raw {
    Some("COMPLETE") | Some("STOP_SEQUENCE") => @provider.V4FinishStop
    Some("MAX_TOKENS") => @provider.V4FinishLength
    Some("ERROR") => @provider.V4FinishError
    Some("TOOL_CALL") => @provider.V4FinishToolCalls
    _ => @provider.V4FinishOther
  }
  { unified, raw, }
}

///|
/// Cohere v2 returns `id`; keep the v1 `generation_id` fallback for proxies.
fn cohere_chat_response_id(value : Json) -> String? {
  match value {
    { "id": String(id), .. } => Some(id)
    { "generation_id": String(id), .. } => Some(id)
    _ => None
  }
}

///|
/// Map citations with document sources to normalized source content. Partial
/// and tool-only citations are retained only when they identify a document.
fn cohere_citation_contents(
  citations : Json?,
  id_generator : @provider_utils.IdGenerator,
) -> Array[@provider.LanguageModelV4Content] {
  let values : Array[Json] = match citations {
    Some(Array(items)) => items
    Some(Object(fields)) => [Json::object(fields)]
    _ => []
  }
  let result : Array[@provider.LanguageModelV4Content] = []
  for citation in values {
    let source = match citation {
      { "sources": Array(sources), .. } => {
        let mut document : Json? = None
        for item in sources {
          match item {
            { "document": Object(document_fields), .. } if document is None =>
              document = Some(Json::object(document_fields))
            _ => ()
          }
        }
        document
      }
      _ => None
    }
    match source {
      Some(document) => {
        let title = match document {
          { "title": String(value), .. } if value != "" => value
          _ => "Document"
        }
        let metadata : Map[String, Json] = Map([])
        match citation {
          Object(fields) => {
            for key in ["start", "end", "text", "sources"] {
              if fields.get(key) is Some(value) && !(value is Null) {
                metadata[key] = value
              }
            }
            if fields.get("type") is Some(String(value)) {
              metadata["citationType"] = Json::string(value)
            }
          }
          _ => ()
        }
        result.push(
          @provider.V4SourceOutput(
            @provider.V4DocumentSource(
              id=id_generator(),
              media_type="text/plain",
              title~,
              filename=None,
              provider_metadata=Map([("cohere", Json::object(metadata))]),
            ),
          ),
        )
      }
      None => ()
    }
  }
  result
}

///|
/// Cohere reports usage under `billed_units`/`tokens` with plain totals.
fn cohere_usage(value : Json?) -> @provider.LanguageModelV4Usage {
  match value {
    Some(object) if object is Object(fields) => {
      let input_tokens = match fields.get("tokens") {
        Some(tokens) =>
          @provider_utils.json_int_field_opt(tokens, "input_tokens")
        None => None
      }
      let output_tokens = match fields.get("tokens") {
        Some(tokens) =>
          @provider_utils.json_int_field_opt(tokens, "output_tokens")
        None => None
      }
      let cached_tokens = @provider_utils.json_int_field_opt(
        object, "cached_tokens",
      )
      let no_cache_tokens = match input_tokens {
        Some(total) => Some(total - cached_tokens.unwrap_or(0))
        None => None
      }
      {
        input_tokens: {
          total: input_tokens,
          no_cache: no_cache_tokens,
          cache_read: cached_tokens,
          cache_write: None,
        },
        output_tokens: {
          total: output_tokens,
          text: output_tokens,
          reasoning: None,
        },
        raw: Some(object),
      }
    }
    _ => @provider.LanguageModelV4Usage::unknown()
  }
}

///|
/// Flatten a Cohere document/image part payload into text or a data URI.
fn cohere_file_url(
  data : @provider.LanguageModelV4FileData,
  media_type : String,
) -> String? raise {
  match data {
    @provider.V4FileUrl(url) => Some(url)
    @provider.V4FileData(payload) =>
      Some("data:\{media_type};base64,\{payload}")
    @provider.V4FileText(text) => Some(text)
    _ =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="file parts with provider references",
      )
  }
}
