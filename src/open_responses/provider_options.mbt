///|
/// Reasoning-summary detail accepted by Open Responses endpoints.
pub(all) enum OpenResponsesReasoningSummary {
  ReasoningSummaryConcise
  ReasoningSummaryDetailed
  ReasoningSummaryAuto
} derive(Debug, Eq)

///|
fn OpenResponsesReasoningSummary::wire_name(
  self : OpenResponsesReasoningSummary,
) -> String {
  match self {
    ReasoningSummaryConcise => "concise"
    ReasoningSummaryDetailed => "detailed"
    ReasoningSummaryAuto => "auto"
  }
}

///|
/// Typed provider options for an Open Responses language model.
pub(all) struct OpenResponsesLanguageModelOptions {
  reasoning_summary : OpenResponsesReasoningSummary?
} derive(Debug, Eq)

///|
/// Construct typed Open Responses language-model options.
pub fn OpenResponsesLanguageModelOptions::new(
  reasoning_summary? : OpenResponsesReasoningSummary,
) -> OpenResponsesLanguageModelOptions {
  { reasoning_summary, }
}

///|
/// Convert typed options to the namespaced provider-options representation.
///
/// The provider name must match the name passed to createOpenResponses.
pub fn OpenResponsesLanguageModelOptions::to_provider_options(
  self : OpenResponsesLanguageModelOptions,
  provider_name? : String = "openResponses",
) -> Map[String, Json] {
  let values : Map[String, Json] = Map(
    [
      ..if self.reasoning_summary is Some(value) {
        [("reasoningSummary", Json::string(value.wire_name()))]
      },
    ],
  )
  Map([(provider_name, Json::object(values))])
}

///|
/// Validated Open Responses provider options.
priv struct OpenResponsesOptions {
  reasoning_summary : String?
}

///|
priv struct ParsedOpenResponsesOptions {
  options : OpenResponsesOptions
  warnings : Array[@provider.Warning]
}

///|
priv struct OpenResponsesPreparedRequest {
  body : Json
  warnings : Array[@provider.Warning]
}

///|
fn open_responses_reserved_fields() -> Array[String] {
  [
    "model", "input", "stream", "instructions", "max_output_tokens", "temperature",
    "top_p", "frequency_penalty", "presence_penalty", "tools", "tool_choice", "text",
  ]
}

///|
fn resolve_open_responses_provider_options(
  provider_options : Map[String, Json],
  provider_name : String,
) -> @provider_utils.ProviderOptionsResolution {
  @provider_utils.resolve_provider_options(
    provider_options,
    provider_name~,
    aliases=["openResponses", "open-responses"],
    reserved_fields=open_responses_reserved_fields(),
    prefer_exact_provider_name=true,
  )
}

///|
fn parse_open_responses_options(
  options : @provider.ChatCallOptions,
  provider_name : String,
) -> ParsedOpenResponsesOptions {
  parse_open_responses_provider_options(options.provider_options, provider_name)
}

///|
fn parse_open_responses_provider_options(
  provider_options : Map[String, Json],
  provider_name : String,
) -> ParsedOpenResponsesOptions {
  let resolution = resolve_open_responses_provider_options(
    provider_options, provider_name,
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let reasoning_summary = reader.take_string(
    "reasoningSummary",
    aliases=["reasoning_summary"],
    allowed=["concise", "detailed", "auto"],
  )
  { options: { reasoning_summary, }, warnings: reader.diagnostics() }
}

///|
fn open_responses_request_warnings(
  options : @provider.ChatCallOptions,
  parsed : ParsedOpenResponsesOptions,
) -> Array[@provider.Warning] {
  let warnings = parsed.warnings.copy()
  if options.stop_sequences.length() > 0 {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="stopSequences",
        details="Open Responses has no portable stop-sequences field.",
      ),
    )
  }
  if options.top_k is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="topK",
        details="The Responses protocol does not define a top-k sampling field.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="seed",
        details="The Responses protocol does not define a seed setting.",
      ),
    )
  }
  if options.reasoning_effort is @provider.Minimal {
    warnings.push(
      @provider.Warning::Compatibility(
        feature="reasoningEffort",
        details="Open Responses maps minimal reasoning effort to low.",
      ),
    )
  }
  for message in options.messages {
    if message.role is @provider.Tool(_) {
      for part in message.parts {
        match part.without_provider_options() {
          @provider.FileReference(..) =>
            warnings.push(
              @provider.Other(
                message="unsupported tool content part type: file with data type: reference",
              ),
            )
          @provider.AudioData(..) =>
            warnings.push(
              @provider.Other(
                message="unsupported tool content part type: audio",
              ),
            )
          _ => ()
        }
      }
    }
  }
  warnings
}

///|
fn prepare_open_responses_request(
  model_id : String,
  options : @provider.ChatCallOptions,
  provider_name : String,
  stream : Bool,
) -> OpenResponsesPreparedRequest raise {
  let parsed = parse_open_responses_options(options, provider_name)
  {
    body: encode_responses_request_with_options(
      model_id,
      options,
      parsed.options,
      stream,
    ),
    warnings: open_responses_request_warnings(options, parsed),
  }
}
