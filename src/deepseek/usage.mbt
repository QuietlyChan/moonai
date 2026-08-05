///|
/// Convert DeepSeek token accounting, including cache reads and reasoning.
pub fn convert_deepseek_usage(json : Json) -> @provider.Usage {
  let input_tokens = @provider_utils.json_int_field(json, "prompt_tokens")
  let output_tokens = @provider_utils.json_int_field(json, "completion_tokens")
  let total_tokens = match
    @provider_utils.json_int_field_opt(json, "total_tokens") {
    Some(value) => value
    None => input_tokens + output_tokens
  }
  let cached_input_tokens = @provider_utils.json_int_field(
    json, "prompt_cache_hit_tokens",
  )
  let reasoning_tokens = match json {
    {
      "completion_tokens_details": { "reasoning_tokens": Number(value, ..), .. },
      ..
    } => value.to_int()
    _ => 0
  }
  {
    input_tokens,
    output_tokens,
    total_tokens,
    reasoning_tokens,
    cached_input_tokens,
    cache_write_input_tokens: 0,
  }
}

///|
fn deepseek_provider_base(provider_name : String) -> String {
  provider_name.strip_suffix(".chat").unwrap_or(provider_name).to_owned()
}

///|
fn deepseek_usage_metadata(
  usage : Json,
  provider_name : String,
) -> Map[String, Json] {
  let details : Map[String, Json] = Map([])
  match @provider_utils.json_int_field_opt(usage, "prompt_cache_hit_tokens") {
    Some(value) =>
      details["promptCacheHitTokens"] = Json::number(value.to_double())
    None => ()
  }
  match @provider_utils.json_int_field_opt(usage, "prompt_cache_miss_tokens") {
    Some(value) =>
      details["promptCacheMissTokens"] = Json::number(value.to_double())
    None => ()
  }
  let metadata : Map[String, Json] = Map([])
  if details.length() > 0 {
    metadata[deepseek_provider_base(provider_name)] = Json::object(details)
  }
  metadata
}
