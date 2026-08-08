///|
priv struct OpenAICompletionV4PreparedRequest {
  body : Json
  warnings : Array[@provider.Warning]
}

///|
fn prepare_openai_completion_v4_request(
  model_id : String,
  options : @provider.LanguageModelV4CallOptions,
  provider_name : String,
  stream : Bool,
  include_usage : Bool,
) -> OpenAICompletionV4PreparedRequest raise {
  let converted = @provider_utils.convert_to_completion_prompt(options.prompt)
  let parsed = parse_openai_completion_provider_options(
    options.provider_options,
    provider_name,
  )
  let warnings = openai_completion_v4_warnings(options)
  for warning in parsed.warnings {
    warnings.push(warning)
  }
  if options.top_k is Some(_) {
    warnings.push(@provider.Warning::unsupported("topK"))
  }
  let stop_sequences = converted.stop_sequences.copy()
  for value in options.stop_sequences {
    stop_sequences.push(value)
  }
  let provider_options = parsed.options
  let body = Json::object(
    Map(
      [
        ("model", Json::string(model_id)),
        ("prompt", Json::string(converted.prompt)),
        ..if stream {
          [("stream", Json::boolean(true))]
        },
        ..if stream && include_usage {
          [("stream_options", ({ "include_usage": true } : Json))]
        },
        ..if provider_options.suffix is Some(value) {
          [("suffix", Json::string(value))]
        },
        ..if provider_options.echo is Some(value) {
          [("echo", Json::boolean(value))]
        },
        ..if provider_options.logit_bias is Some(value) {
          [("logit_bias", value)]
        },
        ..if provider_options.logprobs is Some(value) {
          [("logprobs", Json::number(value.to_double()))]
        },
        ..if provider_options.user is Some(value) {
          [("user", Json::string(value))]
        },
        ..if options.max_output_tokens is Some(value) {
          [("max_tokens", Json::number(value.to_double()))]
        },
        ..if options.temperature is Some(value) {
          [("temperature", Json::number(value))]
        },
        ..if options.top_p is Some(value) {
          [("top_p", Json::number(value))]
        },
        ..if options.frequency_penalty is Some(value) {
          [("frequency_penalty", Json::number(value))]
        },
        ..if options.presence_penalty is Some(value) {
          [("presence_penalty", Json::number(value))]
        },
        ..if options.seed is Some(value) {
          [("seed", Json::number(value.to_double()))]
        },
        ..if stop_sequences.length() > 0 {
          [
            (
              "stop",
              Json::array([ for stop in stop_sequences => Json::string(stop) ]),
            ),
          ]
        },
      ],
    ),
  )
  { body, warnings }
}
