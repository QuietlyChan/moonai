///|
/// Convert DeepSeek token accounting into the lossless V4 usage contract.
fn convert_deepseek_usage(usage : Json?) -> @provider.LanguageModelV4Usage {
  match usage {
    Some(raw) if !(raw is Null) => {
      let input_tokens = @provider_utils.json_int_field(raw, "prompt_tokens")
      let output_tokens = @provider_utils.json_int_field(
        raw, "completion_tokens",
      )
      let cache_read_tokens = @provider_utils.json_int_field(
        raw, "prompt_cache_hit_tokens",
      )
      let reasoning_tokens = match raw {
        {
          "completion_tokens_details": {
            "reasoning_tokens": Number(value, ..),
            ..
          },
          ..
        } => value.to_int()
        _ => 0
      }
      {
        input_tokens: {
          total: Some(input_tokens),
          no_cache: Some(input_tokens - cache_read_tokens),
          cache_read: Some(cache_read_tokens),
          cache_write: None,
        },
        output_tokens: {
          total: Some(output_tokens),
          text: Some(output_tokens - reasoning_tokens),
          reasoning: Some(reasoning_tokens),
        },
        raw: Some(raw),
      }
    }
    _ => @provider_utils.create_null_language_model_usage()
  }
}

///|
fn deepseek_provider_base(provider_name : String) -> String {
  let parts = [ for part in provider_name.split(".") => part ]
  if parts.length() > 0 && !parts[0].trim().is_empty() {
    parts[0].trim().to_owned()
  } else {
    "deepseek"
  }
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
  Map([(deepseek_provider_base(provider_name), Json::object(details))])
}
