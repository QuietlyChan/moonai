///|
/// Encode one OpenAI-compatible image generation request.
pub fn encode_image_request(
  model_id : String,
  options : @moonai.ImageCallOptions,
  include_response_format? : Bool = false,
) -> Json {
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ("prompt", Json::string(options.prompt)),
      ("n", Json::number(options.n.to_double())),
      ..if options.size is Some(value) {
        [("size", Json::string(value))]
      },
      ..if include_response_format {
        [("response_format", Json::string("b64_json"))]
      },
    ],
  )
  for entry in options.provider_options.iter2() {
    let (key, value) = entry
    fields[key] = value
  }
  Json::object(fields)
}
