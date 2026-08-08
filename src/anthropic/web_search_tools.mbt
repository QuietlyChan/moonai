///|
/// Approximate user location sent to Anthropic web search.
pub(all) struct AnthropicWebSearchUserLocation {
  city : String?
  region : String?
  country : String?
  timezone : String?
} derive(Debug, Eq)

///|
/// Construct an approximate web-search location.
pub fn AnthropicWebSearchUserLocation::new(
  city? : String,
  region? : String,
  country? : String,
  timezone? : String,
) -> AnthropicWebSearchUserLocation {
  { city, region, country, timezone }
}

///|
/// Encode the approximate location using the AI SDK argument shape.
pub fn AnthropicWebSearchUserLocation::to_json(
  self : AnthropicWebSearchUserLocation,
) -> Json {
  let fields : Map[String, Json] = Map([("type", Json::string("approximate"))])
  if self.city is Some(value) {
    fields["city"] = Json::string(value)
  }
  if self.region is Some(value) {
    fields["region"] = Json::string(value)
  }
  if self.country is Some(value) {
    fields["country"] = Json::string(value)
  }
  if self.timezone is Some(value) {
    fields["timezone"] = Json::string(value)
  }
  Json::object(fields)
}

///|
fn anthropic_web_search_input_schema() -> Json {
  {
    "type": "object",
    "properties": { "query": { "type": "string" } },
    "required": ["query"],
    "additionalProperties": false,
  }
}

///|
fn anthropic_web_search_output_schema() -> Json {
  {
    "type": "array",
    "items": {
      "type": "object",
      "properties": {
        "url": { "type": "string" },
        "title": { "type": ["string", "null"] },
        "pageAge": { "type": ["string", "null"] },
        "encryptedContent": { "type": "string" },
        "type": { "const": "web_search_result" },
      },
      "required": ["url", "title", "pageAge", "encryptedContent", "type"],
      "additionalProperties": false,
    },
  }
}

///|
fn anthropic_web_search_args(
  max_uses : Int?,
  allowed_domains : Array[String]?,
  blocked_domains : Array[String]?,
  user_location : AnthropicWebSearchUserLocation?,
) -> Json {
  let fields : Map[String, Json] = Map([])
  if max_uses is Some(value) {
    fields["maxUses"] = Json::number(value.to_double())
  }
  if allowed_domains is Some(value) {
    fields["allowedDomains"] = anthropic_json_string_array(value)
  }
  if blocked_domains is Some(value) {
    fields["blockedDomains"] = anthropic_json_string_array(value)
  }
  if user_location is Some(value) {
    fields["userLocation"] = value.to_json()
  }
  Json::object(fields)
}

///|
fn anthropic_web_search_tool(
  id : String,
  max_uses : Int?,
  allowed_domains : Array[String]?,
  blocked_domains : Array[String]?,
  user_location : AnthropicWebSearchUserLocation?,
  on_input_start : @provider_utils.ToolInputStartFunction?,
  on_input_delta : @provider_utils.ToolInputDeltaFunction?,
  on_input_available : @provider_utils.ToolInputAvailableFunction?,
) -> @provider_utils.Tool {
  @provider_utils.create_provider_executed_tool_factory(
    id~,
    input_schema=anthropic_web_search_input_schema(),
    output_schema=anthropic_web_search_output_schema(),
    supports_deferred_results=true,
  ).create(
    args=anthropic_web_search_args(
      max_uses, allowed_domains, blocked_domains, user_location,
    ),
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create Anthropic's 2025-03-05 provider-executed web search tool.
pub fn web_search_20250305(
  max_uses? : Int,
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
  user_location? : AnthropicWebSearchUserLocation,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_web_search_tool(
    "anthropic.web_search_20250305", max_uses, allowed_domains, blocked_domains,
    user_location, on_input_start, on_input_delta, on_input_available,
  )
}

///|
/// Create Anthropic's current provider-executed web search tool.
pub fn web_search_20260209(
  max_uses? : Int,
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
  user_location? : AnthropicWebSearchUserLocation,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_web_search_tool(
    "anthropic.web_search_20260209", max_uses, allowed_domains, blocked_domains,
    user_location, on_input_start, on_input_delta, on_input_available,
  )
}

///|
/// AI SDK-style camel-case spelling.
pub fn webSearch_20250305(
  max_uses? : Int,
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
  user_location? : AnthropicWebSearchUserLocation,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  web_search_20250305(
    max_uses?,
    allowed_domains?,
    blocked_domains?,
    user_location?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// AI SDK-style camel-case spelling.
pub fn webSearch_20260209(
  max_uses? : Int,
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
  user_location? : AnthropicWebSearchUserLocation,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  web_search_20260209(
    max_uses?,
    allowed_domains?,
    blocked_domains?,
    user_location?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}
