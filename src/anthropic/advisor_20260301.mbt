///|
/// Prompt-cache settings for Anthropic's advisor transcript.
pub(all) struct AnthropicAdvisorCaching {
  ttl : AnthropicCacheTtl
} derive(Debug, Eq)

///|
/// Enable ephemeral advisor caching for the selected lifetime.
pub fn AnthropicAdvisorCaching::new(
  ttl~ : AnthropicCacheTtl,
) -> AnthropicAdvisorCaching {
  { ttl, }
}

///|
/// Encode advisor caching arguments using the AI SDK tool schema.
pub fn AnthropicAdvisorCaching::to_json(self : AnthropicAdvisorCaching) -> Json {
  { "type": "ephemeral", "ttl": self.ttl.wire_name() }
}

///|
/// Input schema for advisor calls. The provider always emits an empty input.
fn anthropic_advisor_20260301_input_schema() -> Json {
  {
    "type": "object",
    "properties": Json::empty_object(),
    "additionalProperties": false,
  }
}

///|
/// Normalized output schema used for advisor result validation and replay.
fn anthropic_advisor_20260301_output_schema() -> Json {
  {
    "oneOf": [
      {
        "type": "object",
        "properties": {
          "type": { "const": "advisor_result" },
          "text": { "type": "string" },
        },
        "required": ["type", "text"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "advisor_redacted_result" },
          "encryptedContent": { "type": "string" },
        },
        "required": ["type", "encryptedContent"],
        "additionalProperties": false,
      },
      {
        "type": "object",
        "properties": {
          "type": { "const": "advisor_tool_result_error" },
          "errorCode": { "type": "string" },
        },
        "required": ["type", "errorCode"],
        "additionalProperties": false,
      },
    ],
  }
}

///|
/// Create Anthropic's high-level advisor tool.
///
/// The provider executes the advisor and may return its result after other
/// tool calls have completed, so deferred results are enabled.
pub fn advisor_20260301(
  model~ : String,
  max_uses? : Int,
  caching? : AnthropicAdvisorCaching,
  on_input_start? : @provider_utils.ToolInputStartFunction,
  on_input_delta? : @provider_utils.ToolInputDeltaFunction,
  on_input_available? : @provider_utils.ToolInputAvailableFunction,
) -> @provider_utils.Tool {
  let args : Map[String, Json] = Map([("model", Json::string(model))])
  if max_uses is Some(value) {
    args["maxUses"] = Json::number(value.to_double())
  }
  if caching is Some(value) {
    args["caching"] = value.to_json()
  }
  @provider_utils.create_provider_executed_tool_factory(
    id="anthropic.advisor_20260301",
    input_schema=anthropic_advisor_20260301_input_schema(),
    output_schema=anthropic_advisor_20260301_output_schema(),
    supports_deferred_results=true,
  ).create(
    args=Json::object(args),
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}
