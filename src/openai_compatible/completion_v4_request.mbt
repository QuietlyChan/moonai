///|
priv struct OpenAICompatibleCompletionV4PreparedRequest {
  body : Json
  warnings : Array[@provider.Warning]
}

///|
fn completion_option_wire_key(key : String) -> String {
  match key {
    "logitBias" => "logit_bias"
    other => other
  }
}

///|
fn prepare_compatible_completion_v4_request(
  model_id : String,
  options : @provider.LanguageModelV4CallOptions,
  provider_name : String,
  stream : Bool,
  include_usage : Bool,
) -> OpenAICompatibleCompletionV4PreparedRequest raise {
  let converted = @provider_utils.convert_to_completion_prompt(options.prompt)
  let resolution = resolve_compatible_options(
    options.provider_options,
    provider_name,
    completion_reserved_fields(),
  )
  let warnings = compatible_completion_v4_warnings(options)
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  if options.top_k is Some(_) {
    warnings.push(@provider.Warning::unsupported("topK"))
  }
  let stop_sequences = converted.stop_sequences.copy()
  for value in options.stop_sequences {
    stop_sequences.push(value)
  }
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ("prompt", Json::string(converted.prompt)),
      ..if stream {
        [("stream", Json::boolean(true))]
      },
      ..if stream && include_usage {
        [("stream_options", ({ "include_usage": true } : Json))]
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
  )
  for entry in resolution.values.iter2() {
    let (key, value) = entry
    fields[completion_option_wire_key(key)] = value
  }
  { body: Json::object(fields), warnings }
}
