///|
/// Alibaba prompt-token details returned by the Chat Completions endpoint.
pub(all) struct AlibabaPromptTokensDetails {
  cached_tokens : Int?
  cache_creation_input_tokens : Int?
} derive(Debug, Eq)

///|
/// Construct Alibaba prompt-token details.
pub fn AlibabaPromptTokensDetails::new(
  cached_tokens? : Int,
  cache_creation_input_tokens? : Int,
) -> AlibabaPromptTokensDetails {
  { cached_tokens, cache_creation_input_tokens }
}

///|
fn AlibabaPromptTokensDetails::to_json(
  self : AlibabaPromptTokensDetails,
) -> Json {
  let fields : Map[String, Json] = Map([])
  if self.cached_tokens is Some(value) {
    fields["cached_tokens"] = Json::number(value.to_double())
  }
  if self.cache_creation_input_tokens is Some(value) {
    fields["cache_creation_input_tokens"] = Json::number(value.to_double())
  }
  Json::object(fields)
}

///|
fn AlibabaPromptTokensDetails::from_json(
  value : Json,
) -> AlibabaPromptTokensDetails? {
  match value {
    Object(_) =>
      Some({
        cached_tokens: @provider_utils.json_int_field_opt(
          value, "cached_tokens",
        ),
        cache_creation_input_tokens: @provider_utils.json_int_field_opt(
          value, "cache_creation_input_tokens",
        ),
      })
    _ => None
  }
}

///|
/// Alibaba completion-token details returned by reasoning-capable models.
pub(all) struct AlibabaCompletionTokensDetails {
  reasoning_tokens : Int?
} derive(Debug, Eq)

///|
/// Construct Alibaba completion-token details.
pub fn AlibabaCompletionTokensDetails::new(
  reasoning_tokens? : Int,
) -> AlibabaCompletionTokensDetails {
  { reasoning_tokens, }
}

///|
fn AlibabaCompletionTokensDetails::to_json(
  self : AlibabaCompletionTokensDetails,
) -> Json {
  let fields : Map[String, Json] = Map([])
  if self.reasoning_tokens is Some(value) {
    fields["reasoning_tokens"] = Json::number(value.to_double())
  }
  Json::object(fields)
}

///|
fn AlibabaCompletionTokensDetails::from_json(
  value : Json,
) -> AlibabaCompletionTokensDetails? {
  match value {
    Object(_) =>
      Some({
        reasoning_tokens: @provider_utils.json_int_field_opt(
          value, "reasoning_tokens",
        ),
      })
    _ => None
  }
}

///|
/// Raw token accounting returned by Alibaba Chat Completions.
///
/// This mirrors the exported `AlibabaUsage` type in the AI SDK. Optional and
/// JSON `null` fields both map to `None` at the typed MoonBit boundary.
pub(all) struct AlibabaUsage {
  prompt_tokens : Int?
  completion_tokens : Int?
  total_tokens : Int?
  prompt_tokens_details : AlibabaPromptTokensDetails?
  completion_tokens_details : AlibabaCompletionTokensDetails?
} derive(Debug, Eq)

///|
/// Construct a provider-specific Alibaba usage value.
pub fn AlibabaUsage::new(
  prompt_tokens? : Int,
  completion_tokens? : Int,
  total_tokens? : Int,
  prompt_tokens_details? : AlibabaPromptTokensDetails,
  completion_tokens_details? : AlibabaCompletionTokensDetails,
) -> AlibabaUsage {
  {
    prompt_tokens,
    completion_tokens,
    total_tokens,
    prompt_tokens_details,
    completion_tokens_details,
  }
}

///|
/// Decode Alibaba's raw usage object into its provider-specific typed view.
pub fn AlibabaUsage::from_json(value : Json) -> AlibabaUsage? {
  match value {
    Object(_) =>
      Some({
        prompt_tokens: @provider_utils.json_int_field_opt(
          value, "prompt_tokens",
        ),
        completion_tokens: @provider_utils.json_int_field_opt(
          value, "completion_tokens",
        ),
        total_tokens: @provider_utils.json_int_field_opt(value, "total_tokens"),
        prompt_tokens_details: match value {
          { "prompt_tokens_details": details, .. } =>
            AlibabaPromptTokensDetails::from_json(details)
          _ => None
        },
        completion_tokens_details: match value {
          { "completion_tokens_details": details, .. } =>
            AlibabaCompletionTokensDetails::from_json(details)
          _ => None
        },
      })
    _ => None
  }
}

///|
/// Encode the typed Alibaba usage view using the wire field names.
pub fn AlibabaUsage::to_json(self : AlibabaUsage) -> Json {
  let fields : Map[String, Json] = Map([])
  if self.prompt_tokens is Some(value) {
    fields["prompt_tokens"] = Json::number(value.to_double())
  }
  if self.completion_tokens is Some(value) {
    fields["completion_tokens"] = Json::number(value.to_double())
  }
  if self.total_tokens is Some(value) {
    fields["total_tokens"] = Json::number(value.to_double())
  }
  if self.prompt_tokens_details is Some(value) {
    fields["prompt_tokens_details"] = value.to_json()
  }
  if self.completion_tokens_details is Some(value) {
    fields["completion_tokens_details"] = value.to_json()
  }
  Json::object(fields)
}

///|
/// Convert Alibaba token accounting into the V4 usage contract, including
/// prompt-cache creation details that are not part of the generic compatible
/// shape.
fn convert_alibaba_chat_usage(usage : Json?) -> @provider.LanguageModelV4Usage {
  let base = @openai_compatible.convert_openai_compatible_chat_usage(usage)
  let typed_usage = match usage {
    Some(value) => AlibabaUsage::from_json(value)
    None => None
  }
  let cache_write_input_tokens = match typed_usage {
    Some(value) =>
      match value.prompt_tokens_details {
        Some(details) => details.cache_creation_input_tokens.unwrap_or(0)
        None => 0
      }
    _ => 0
  }
  {
    input_tokens: {
      total: base.input_tokens.total,
      no_cache: Some(
        base.input_tokens.total.unwrap_or(0) -
        base.input_tokens.cache_read.unwrap_or(0) -
        cache_write_input_tokens,
      ),
      cache_read: base.input_tokens.cache_read,
      cache_write: Some(cache_write_input_tokens),
    },
    output_tokens: base.output_tokens,
    raw: base.raw,
  }
}
