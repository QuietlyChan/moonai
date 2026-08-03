///|
/// Encode a legacy OpenAI completion request.
pub fn encode_completion_request(
  model_id : String,
  options : @moonai.CompletionOptions,
  include_usage? : Bool = true,
  stream? : Bool = true,
) -> Json {
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
  for entry in options.provider_options.iter2() {
    let (key, value) = entry
    fields[key] = value
  }
  Json::object(fields)
}
