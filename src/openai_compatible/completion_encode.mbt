///|
/// Encode a legacy OpenAI completion request.
pub fn encode_completion_request(
  model_id : String,
  options : @provider.CompletionOptions,
  include_usage? : Bool = false,
  stream? : Bool = true,
  provider_name? : String = "",
) -> Json {
  let provider_options = resolve_compatible_options(
      options.provider_options,
      provider_name,
      completion_reserved_fields(),
    ).values
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ("prompt", Json::string(options.prompt)),
      ..if stream {
        [("stream", Json::boolean(true))]
      },
      ..if stream && include_usage {
        [("stream_options", ({ "include_usage": true } : Json))]
      },
      ..if options.suffix is Some(value) {
        [("suffix", Json::string(value))]
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
      ..if options.stop_sequences.length() > 0 {
        [
          (
            "stop",
            Json::array(
              [
                for stop in options.stop_sequences => Json::string(stop)
              ],
            ),
          ),
        ]
      },
    ],
  )
  for entry in provider_options.iter2() {
    let (key, value) = entry
    fields[completion_option_wire_key(key)] = value
  }
  Json::object(fields)
}

///|
/// Normalize the option names used by the AI SDK schemas to the OpenAI wire
/// names. Unknown options remain untouched for provider-specific extensions.
fn completion_option_wire_key(key : String) -> String {
  match key {
    "logitBias" => "logit_bias"
    "maxTokens" => "max_tokens"
    "frequencyPenalty" => "frequency_penalty"
    "presencePenalty" => "presence_penalty"
    "stopSequences" => "stop"
    other => other
  }
}
