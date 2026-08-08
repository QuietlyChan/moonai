///|
fn openai_prompt_option(options : Map[String, Json], field : String) -> Json? {
  match options.get("openai") {
    Some(Object(values)) =>
      match values.get(field) {
        Some(Null) | None => None
        Some(value) => Some(value)
      }
    _ => None
  }
}

///|
fn openai_prompt_cache_breakpoint(options : Map[String, Json]) -> Json? {
  openai_prompt_option(options, "promptCacheBreakpoint")
}

///|
fn openai_image_detail(options : Map[String, Json]) -> String? {
  match openai_prompt_option(options, "imageDetail") {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn with_openai_prompt_cache_breakpoint(
  content : Json,
  options : Map[String, Json],
) -> Json {
  guard content is Object(fields) else { return content }
  guard openai_prompt_cache_breakpoint(options) is Some(breakpoint) else {
    return content
  }
  let result = @provider.copy_provider_metadata(fields)
  result["prompt_cache_breakpoint"] = breakpoint
  Json::object(result)
}

///|
fn openai_image_url_value(url : String, options : Map[String, Json]) -> Json {
  let fields : Map[String, Json] = Map([("url", Json::string(url))])
  if openai_image_detail(options) is Some(detail) {
    fields["detail"] = Json::string(detail)
  }
  Json::object(fields)
}

///|
fn openai_text_content_with_breakpoint(
  text : String,
  options : Map[String, Json],
) -> Json {
  with_openai_prompt_cache_breakpoint(
    ({ "type": "text", "text": text } : Json),
    options,
  )
}

///|
fn openai_data_uri(media_type : String, data : String) -> String {
  "data:\{media_type};base64,\{data}"
}
