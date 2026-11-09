///|
priv struct PerplexityDecodedAgentResponse {
  content : Array[@provider.LanguageModelV4Content]
  finish_reason : @provider.LanguageModelV4FinishReason
  usage : @provider.LanguageModelV4Usage
  provider_metadata : Map[String, Json]
  response : @provider.ResponseMetadata?
}

///|
fn perplexity_agent_id(value : Json) -> String? {
  match value {
    Number(number, ..) => Some(number.to_int().to_string())
    String(text) => Some(text)
    _ => None
  }
}

///|
fn perplexity_agent_optional_json(value : Json, field : String) -> Json {
  match value {
    Object(fields) => fields.get(field).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn perplexity_agent_search_queries(value : Json) -> Array[String] {
  match value {
    { "queries": Array(queries), .. } => {
      let result : Array[String] = []
      for query in queries {
        match query {
          String(text) => if !result.contains(text) { result.push(text) }
          _ => ()
        }
      }
      result
    }
    _ => []
  }
}

///|
fn perplexity_agent_search_result_source(
  value : Json,
  id_generator : @provider_utils.IdGenerator,
) -> @provider.LanguageModelV4Content? {
  match value {
    { "title": String(title), "url": String(url), .. } if url != "" => {
      let result_id = perplexity_agent_optional_json(value, "id")
      let metadata : Map[String, Json] = Map([
        ("resultId", result_id),
        ("snippet", perplexity_agent_optional_json(value, "snippet")),
        ("date", perplexity_agent_optional_json(value, "date")),
        ("lastUpdated", perplexity_agent_optional_json(value, "last_updated")),
        ("source", perplexity_agent_optional_json(value, "source")),
      ])
      Some(
        @provider.V4SourceOutput(
          @provider.V4UrlSource(
            id=match perplexity_agent_id(result_id) {
              Some(id) => id
              None => id_generator()
            },
            url~,
            title=Some(title),
            provider_metadata=Map([("perplexity", Json::object(metadata))]),
          ),
        ),
      )
    }
    _ => None
  }
}

///|
fn perplexity_agent_fetch_result_source(
  value : Json,
  id_generator : @provider_utils.IdGenerator,
) -> @provider.LanguageModelV4Content? {
  match value {
    { "title": String(title), "url": String(url), .. } if url != "" =>
      Some(
        @provider.V4SourceOutput(
          @provider.V4UrlSource(
            id=id_generator(),
            url~,
            title=Some(title),
            provider_metadata=Map([
              (
                "perplexity",
                (
                  {
                    "snippet": perplexity_agent_optional_json(value, "snippet"),
                  } : Json),
              ),
            ]),
          ),
        ),
      )
    _ => None
  }
}

///|
fn perplexity_agent_annotation_source(
  value : Json,
  id_generator : @provider_utils.IdGenerator,
) -> @provider.LanguageModelV4Content? {
  match value {
    { "url": String(url), .. } if url != "" =>
      Some(
        @provider.V4SourceOutput(
          @provider.V4UrlSource(
            id=id_generator(),
            url~,
            title=@provider_utils.json_string_field(value, "title"),
            provider_metadata=Map([]),
          ),
        ),
      )
    _ => None
  }
}

///|
fn perplexity_agent_add_source(
  content : Array[@provider.LanguageModelV4Content],
  urls : Array[String],
  content_indexes : Array[Int32],
  has_result_id : Array[Bool],
  source : @provider.LanguageModelV4Content,
) -> Unit {
  let (url, ranked) = match source {
    @provider.V4SourceOutput(
      @provider.V4UrlSource(url~, provider_metadata~, ..)
    ) => {
      let ranked = match provider_metadata.get("perplexity") {
        Some({ "resultId": Number(_, ..), .. }) => true
        _ => false
      }
      (url, ranked)
    }
    _ => return
  }
  match urls.search_by(value => value == url) {
    Some(index) if ranked && !has_result_id[index] => {
      content[content_indexes[index]] = source
      has_result_id[index] = true
    }
    Some(_) => ()
    None => {
      urls.push(url)
      content_indexes.push(content.length())
      has_result_id.push(ranked)
      content.push(source)
    }
  }
}

///|
fn perplexity_agent_output_items(
  value : Json,
  id_generator : @provider_utils.IdGenerator,
) -> (Array[@provider.LanguageModelV4Content], Array[String], Bool) raise {
  let output = match value {
    { "output": Array(items), .. } => items
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Perplexity Agent API response has no output array",
        data=value,
      )
  }
  let content : Array[@provider.LanguageModelV4Content] = []
  let source_urls : Array[String] = []
  let source_content_indexes : Array[Int32] = []
  let source_has_result_ids : Array[Bool] = []
  let search_queries : Array[String] = []
  let mut has_function_call = false
  for item in output {
    match item {
      { "type": "message", "content": Array(parts), .. } =>
        for part in parts {
          if part is { "type": "output_text", "text": String(text), .. } {
            content.push(
              @provider.V4TextOutput({ text, provider_metadata: Map([]), }),
            )
          }
          if part is { "annotations": Array(annotations), .. } {
            for annotation in annotations {
              match
                perplexity_agent_annotation_source(annotation, id_generator) {
                Some(source) =>
                  perplexity_agent_add_source(
                    content, source_urls, source_content_indexes, source_has_result_ids,
                    source,
                  )
                None => ()
              }
            }
          }
        }
      { "type": "search_results", .. } => {
        for query in perplexity_agent_search_queries(item) {
          if !search_queries.contains(query) {
            search_queries.push(query)
          }
        }
        match item {
          { "results": Array(results), .. } =>
            for result in results {
              match
                perplexity_agent_search_result_source(result, id_generator) {
                Some(source) =>
                  perplexity_agent_add_source(
                    content, source_urls, source_content_indexes, source_has_result_ids,
                    source,
                  )
                None => ()
              }
            }
          _ => ()
        }
      }
      { "type": "fetch_url_results", "contents": Array(results), .. } =>
        for result in results {
          match perplexity_agent_fetch_result_source(result, id_generator) {
            Some(source) =>
              perplexity_agent_add_source(
                content, source_urls, source_content_indexes, source_has_result_ids,
                source,
              )
            None => ()
          }
        }
      {
        "type": "function_call",
        "call_id": String(call_id),
        "name": String(name),
        "arguments": String(arguments),
        ..
      } => {
        has_function_call = true
        let item_id = @provider_utils.json_string_field(item, "id")
        let thought_signature = @provider_utils.json_string_field(
          item, "thought_signature",
        )
        content.push(
          @provider.V4ToolCallOutput({
            tool_call_id: call_id,
            tool_name: name,
            input: arguments,
            provider_executed: false,
            dynamic: false,
            provider_metadata: Map([
              (
                "perplexity",
                (
                  { "itemId": item_id, "thoughtSignature": thought_signature } :
                  Json),
              ),
            ]),
          }),
        )
      }
      _ => ()
    }
  }
  (content, search_queries, has_function_call)
}

///|
fn perplexity_agent_usage(value : Json?) -> @provider.LanguageModelV4Usage {
  match value {
    Some({ .. } as usage) => {
      let input_tokens = @provider_utils.json_int_field_opt(
        usage, "input_tokens",
      ).unwrap_or(0)
      let output_tokens = @provider_utils.json_int_field_opt(
        usage, "output_tokens",
      ).unwrap_or(0)
      let input_details = perplexity_agent_optional_json(
        usage, "input_tokens_details",
      )
      let output_details = perplexity_agent_optional_json(
        usage, "output_tokens_details",
      )
      let cached = @provider_utils.json_int_field_opt(
        input_details, "cache_read_input_tokens",
      ).unwrap_or(
        @provider_utils.json_int_field_opt(input_details, "cached_tokens").unwrap_or(
          0,
        ),
      )
      let cache_write = @provider_utils.json_int_field_opt(
        input_details, "cache_creation_input_tokens",
      ).unwrap_or(0)
      let reasoning = @provider_utils.json_int_field_opt(
        output_details, "reasoning_tokens",
      ).unwrap_or(0)
      {
        input_tokens: {
          total: Some(input_tokens),
          no_cache: Some(
            perplexity_non_negative(input_tokens - cached - cache_write),
          ),
          cache_read: Some(cached),
          cache_write: Some(cache_write),
        },
        output_tokens: {
          total: Some(output_tokens),
          text: Some(perplexity_non_negative(output_tokens - reasoning)),
          reasoning: Some(reasoning),
        },
        raw: Some(usage),
      }
    }
    _ => @provider_utils.create_null_language_model_usage()
  }
}

///|
fn perplexity_non_negative(value : Int32) -> Int32 {
  if value < 0 {
    0
  } else {
    value
  }
}

///|
fn perplexity_agent_provider_metadata(
  usage : Json?,
  search_queries : Array[String],
) -> Map[String, Json] {
  let perplexity : Map[String, Json] = Map([
    (
      "searchQueries",
      if search_queries.length() == 0 {
        Json::null()
      } else {
        Json::array([ for query in search_queries => Json::string(query) ])
      },
    ),
    ("images", Json::null()),
  ])
  let cost = perplexity_agent_optional_json(
    usage.unwrap_or(Json::null()),
    "cost",
  )
  if cost is Object(fields) {
    let mapped : Map[String, Json] = Map([])
    for
      (source, target) in [
        ("input_cost", "inputTokensCost"),
        ("output_cost", "outputTokensCost"),
        ("total_cost", "totalCost"),
        ("currency", "currency"),
        ("cache_creation_cost", "cacheCreationCost"),
        ("cache_read_cost", "cacheReadCost"),
        ("tool_calls_cost", "toolCallsCost"),
      ] {
      mapped[target] = fields.get(source).unwrap_or(Json::null())
    }
    mapped["requestCost"] = Json::null()
    perplexity["cost"] = Json::object(mapped)
  } else {
    perplexity["cost"] = Json::null()
  }
  let tool_calls = perplexity_agent_optional_json(
    usage.unwrap_or(Json::null()),
    "tool_calls_details",
  )
  match tool_calls {
    Object(entries) => {
      let mapped : Map[String, Json] = Map([])
      let mut search_invocations = 0
      for entry in entries.iter2() {
        let (name, details) = entry
        let invocation = @provider_utils.json_int_field_opt(
          details, "invocation",
        )
        mapped[name] = {
          "invocation": match invocation {
            Some(value) => Json::number(value.to_double())
            None => Json::null()
          },
        }
        if name.contains("search") {
          search_invocations = search_invocations + invocation.unwrap_or(0)
        }
      }
      perplexity["toolCalls"] = Json::object(mapped)
      perplexity["usage"] = {
        "citationTokens": Json::null(),
        "numSearchQueries": Json::number(search_invocations.to_double()),
      }
    }
    _ => {
      perplexity["toolCalls"] = Json::null()
      perplexity["usage"] = {
        "citationTokens": Json::null(),
        "numSearchQueries": Json::null(),
      }
    }
  }
  Map([("perplexity", Json::object(perplexity))])
}

///|
fn perplexity_agent_decoded_response(
  value : Json,
  id_generator : @provider_utils.IdGenerator,
) -> PerplexityDecodedAgentResponse raise {
  match value {
    { "error": Object(error), .. } =>
      raise @provider.InvalidResponseDataError(
        message=@provider_utils.json_string_field(
          Json::object(error),
          "message",
        ).unwrap_or("Perplexity response failed"),
        data=value,
      )
    _ => ()
  }
  let status = @provider_utils.json_string_field(value, "status").unwrap_or("")
  if status == "failed" {
    raise @provider.InvalidResponseDataError(
      message="Perplexity response failed",
      data=value,
    )
  }
  if perplexity_agent_response_validation_error(value) is Some(error) {
    raise @provider.InvalidResponseDataError(
      message="Invalid Perplexity Agent API response: " + error,
      data=value,
    )
  }
  let (content, search_queries, has_function_call) = perplexity_agent_output_items(
    value, id_generator,
  )
  let incomplete_reason = match value {
    { "incomplete_details": { "reason": String(reason), .. }, .. } =>
      Some(reason)
    _ => None
  }
  let finish_reason = perplexity_map_agent_finish_reason(
    status, incomplete_reason, has_function_call,
  )
  let response = @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(value, "id"),
    model?=@provider_utils.json_string_field(value, "model"),
    created?=@provider_utils.json_int_field_opt(value, "created_at"),
  )
  let usage = match value {
    { "usage": usage, .. } if !(usage is Null) => Some(usage)
    _ => None
  }
  {
    content,
    finish_reason,
    usage: perplexity_agent_usage(usage),
    provider_metadata: perplexity_agent_provider_metadata(usage, search_queries),
    response: if response.is_empty() {
      None
    } else {
      Some(response)
    },
  }
}
