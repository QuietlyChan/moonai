///|
fn openai_compatible_wire_metadata(
  options : Map[String, Json],
) -> Map[String, Json] {
  match options.get("openaiCompatible") {
    Some(Object(values)) => @provider.copy_provider_metadata(values)
    _ => Map([])
  }
}

///|
fn with_openai_compatible_wire_metadata(
  content : Json,
  options : Map[String, Json],
) -> Json {
  guard content is Object(fields) else { return content }
  let result = @provider.copy_provider_metadata(fields)
  for entry in openai_compatible_wire_metadata(options).iter2() {
    result[entry.0] = entry.1
  }
  Json::object(result)
}

///|
fn data_uri(media_type : String, data : String) -> String {
  "data:\{media_type};base64,\{data}"
}

///|
fn chat_option_wire_key(key : String) -> String {
  match key {
    "reasoningEffort" => "reasoning_effort"
    "textVerbosity" => "verbosity"
    "strictJsonSchema" => "strict_json_schema"
    other => other
  }
}
