///|
/// Citation settings for Anthropic's provider-executed web fetch tool.
pub(all) struct AnthropicWebFetchCitations {
  enabled : Bool
} derive(Debug, Eq)

///|
/// Construct web-fetch citation settings.
pub fn AnthropicWebFetchCitations::new(
  enabled~ : Bool,
) -> AnthropicWebFetchCitations {
  { enabled, }
}

///|
/// Encode citation settings using the AI SDK provider-tool argument shape.
pub fn AnthropicWebFetchCitations::to_json(
  self : AnthropicWebFetchCitations,
) -> Json {
  { "enabled": self.enabled }
}

///|
fn anthropic_web_fetch_input_schema() -> Json {
  {
    "type": "object",
    "properties": { "url": { "type": "string" } },
    "required": ["url"],
    "additionalProperties": false,
  }
}

///|
fn anthropic_web_fetch_output_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "type": { "const": "web_fetch_result" },
      "url": { "type": "string" },
      "content": {
        "type": "object",
        "properties": {
          "type": { "const": "document" },
          "title": { "type": ["string", "null"] },
          "citations": {
            "type": "object",
            "properties": { "enabled": { "type": "boolean" } },
            "required": ["enabled"],
            "additionalProperties": false,
          },
          "source": {
            "oneOf": [
              {
                "type": "object",
                "properties": {
                  "type": { "const": "base64" },
                  "mediaType": { "const": "application/pdf" },
                  "data": { "type": "string" },
                },
                "required": ["type", "mediaType", "data"],
                "additionalProperties": false,
              },
              {
                "type": "object",
                "properties": {
                  "type": { "const": "text" },
                  "mediaType": { "const": "text/plain" },
                  "data": { "type": "string" },
                },
                "required": ["type", "mediaType", "data"],
                "additionalProperties": false,
              },
            ],
          },
        },
        "required": ["type", "title", "source"],
        "additionalProperties": false,
      },
      "retrievedAt": { "type": ["string", "null"] },
    },
    "required": ["type", "url", "content", "retrievedAt"],
    "additionalProperties": false,
  }
}

///|
fn anthropic_json_string_array(values : Array[String]) -> Json {
  Json::array([ for value in values => Json::string(value) ])
}

///|
fn anthropic_web_fetch_args(
  max_uses : Int?,
  allowed_domains : Array[String]?,
  blocked_domains : Array[String]?,
  citations : AnthropicWebFetchCitations?,
  max_content_tokens : Int?,
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
  if citations is Some(value) {
    fields["citations"] = value.to_json()
  }
  if max_content_tokens is Some(value) {
    fields["maxContentTokens"] = Json::number(value.to_double())
  }
  Json::object(fields)
}

///|
fn anthropic_web_fetch_tool(
  id : String,
  max_uses : Int?,
  allowed_domains : Array[String]?,
  blocked_domains : Array[String]?,
  citations : AnthropicWebFetchCitations?,
  max_content_tokens : Int?,
  on_input_start : @provider_utils.ToolInputStartFunction?,
  on_input_delta : @provider_utils.ToolInputDeltaFunction?,
  on_input_available : @provider_utils.ToolInputAvailableFunction?,
) -> @provider_utils.Tool {
  @provider_utils.create_provider_executed_tool_factory(
    id~,
    input_schema=anthropic_web_fetch_input_schema(),
    output_schema=anthropic_web_fetch_output_schema(),
    supports_deferred_results=true,
  ).create(
    args=anthropic_web_fetch_args(
      max_uses, allowed_domains, blocked_domains, citations, max_content_tokens,
    ),
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create Anthropic's 2025-09-10 provider-executed web fetch tool.
pub fn web_fetch_20250910(
  max_uses? : Int,
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
  citations? : AnthropicWebFetchCitations,
  max_content_tokens? : Int,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_web_fetch_tool(
    "anthropic.web_fetch_20250910", max_uses, allowed_domains, blocked_domains, citations,
    max_content_tokens, on_input_start, on_input_delta, on_input_available,
  )
}

///|
/// Create Anthropic's current provider-executed web fetch tool.
pub fn web_fetch_20260209(
  max_uses? : Int,
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
  citations? : AnthropicWebFetchCitations,
  max_content_tokens? : Int,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  anthropic_web_fetch_tool(
    "anthropic.web_fetch_20260209", max_uses, allowed_domains, blocked_domains, citations,
    max_content_tokens, on_input_start, on_input_delta, on_input_available,
  )
}

///|
/// AI SDK-style camel-case spelling.
pub fn webFetch_20250910(
  max_uses? : Int,
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
  citations? : AnthropicWebFetchCitations,
  max_content_tokens? : Int,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  web_fetch_20250910(
    max_uses?,
    allowed_domains?,
    blocked_domains?,
    citations?,
    max_content_tokens?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// AI SDK-style camel-case spelling.
pub fn webFetch_20260209(
  max_uses? : Int,
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
  citations? : AnthropicWebFetchCitations,
  max_content_tokens? : Int,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  web_fetch_20260209(
    max_uses?,
    allowed_domains?,
    blocked_domains?,
    citations?,
    max_content_tokens?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}
