///|
fn openai_provider_metadata_key(_provider_name : String) -> String {
  "openai"
}

///|
/// Responses uses Azure's namespace when the configured provider identifier
/// contains `azure`; all other provider names retain OpenAI's namespace.
fn openai_responses_provider_metadata_key(provider_name : String) -> String {
  if provider_name.contains("azure") {
    "azure"
  } else {
    "openai"
  }
}

///|
fn openai_error_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "error": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn openai_chat_metadata_fields(json : Json) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([])
  match json {
    {
      "usage": {
        "completion_tokens_details": {
          "accepted_prediction_tokens": Number(value, ..),
          ..
        },
        ..
      },
      ..
    } => fields["acceptedPredictionTokens"] = Json::number(value)
    _ => ()
  }
  match json {
    {
      "usage": {
        "completion_tokens_details": {
          "rejected_prediction_tokens": Number(value, ..),
          ..
        },
        ..
      },
      ..
    } => fields["rejectedPredictionTokens"] = Json::number(value)
    _ => ()
  }
  match json {
    {
      "choices": [{ "logprobs": { "content": Array(values), .. }, .. }, ..],
      ..
    } => fields["logprobs"] = Json::array(values)
    _ => ()
  }
  fields
}

///|
fn openai_chat_metadata(
  json : Json,
  provider_name : String,
) -> Map[String, Json] {
  let provider_key = openai_provider_metadata_key(provider_name)
  Map([(provider_key, Json::object(openai_chat_metadata_fields(json)))])
}

///|
fn append_openai_responses_logprobs(
  values : Array[Json],
  logprobs : Array[Json],
) -> Unit {
  if values.length() > 0 {
    logprobs.push(Json::array(values))
  }
}

///|
fn update_openai_responses_metadata(
  json : Json,
  fields : Map[String, Json],
  logprobs : Array[Json],
) -> Unit {
  match json {
    { "id": String(value), .. } => fields["responseId"] = Json::string(value)
    _ => ()
  }
  match json {
    { "service_tier": String(value), .. } =>
      fields["serviceTier"] = Json::string(value)
    _ => ()
  }
  match json {
    { "reasoning": { "context": String(value), .. }, .. } =>
      fields["reasoningContext"] = Json::string(value)
    _ => ()
  }
  match json {
    { "type": "response.output_text.delta", "logprobs": Array(values), .. } =>
      append_openai_responses_logprobs(values, logprobs)
    _ => ()
  }
  match json {
    { "output": Array(items), .. } =>
      for item in items {
        match item {
          { "type": "message", "content": Array(parts), .. } =>
            for part in parts {
              match part {
                { "logprobs": Array(values), .. } =>
                  append_openai_responses_logprobs(values, logprobs)
                _ => ()
              }
            }
          _ => ()
        }
      }
    _ => ()
  }
  match json {
    { "response": Object(_) as response, .. } =>
      update_openai_responses_metadata(response, fields, logprobs)
    _ => ()
  }
}

///|
fn build_openai_responses_metadata(
  provider_key : String,
  fields : Map[String, Json],
  logprobs : Array[Json],
) -> Map[String, Json] {
  let result_fields = @provider.copy_provider_metadata(fields)
  if logprobs.length() > 0 {
    result_fields["logprobs"] = Json::array(logprobs.copy())
  }
  Map([(provider_key, Json::object(result_fields))])
}

///|
fn openai_responses_metadata(
  json : Json,
  provider_name : String,
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([])
  let logprobs : Array[Json] = []
  update_openai_responses_metadata(json, fields, logprobs)
  build_openai_responses_metadata(
    openai_responses_provider_metadata_key(provider_name),
    fields,
    logprobs,
  )
}

///|
fn openai_responses_stream_metadata(
  provider_name : String,
) -> ((Json) -> Unit, () -> Map[String, Json]) {
  let provider_key = openai_responses_provider_metadata_key(provider_name)
  let fields : Map[String, Json] = Map([])
  let logprobs : Array[Json] = []
  let observe_json = json => {
    update_openai_responses_metadata(json, fields, logprobs)
  }
  let build_metadata = () => {
    build_openai_responses_metadata(provider_key, fields, logprobs)
  }
  (observe_json, build_metadata)
}
