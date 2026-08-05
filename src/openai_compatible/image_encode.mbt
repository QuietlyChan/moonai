///|
/// Encode one OpenAI-compatible image generation request.
pub fn encode_image_request(
  model_id : String,
  options : @provider.ImageCallOptions,
  include_response_format? : Bool = false,
  provider_name? : String = "",
) -> Json {
  let provider_options = resolve_compatible_options(
      options.provider_options,
      provider_name,
      image_reserved_fields(),
    ).values
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
  for entry in provider_options.iter2() {
    let (key, value) = entry
    fields[image_option_wire_key(key)] = value
  }
  Json::object(fields)
}

///|
/// Normalize common image provider option names while keeping unknown fields
/// available to OpenAI-compatible services.
fn image_option_wire_key(key : String) -> String {
  match key {
    "outputFormat" => "output_format"
    "outputCompression" => "output_compression"
    "inputFidelity" => "input_fidelity"
    other => other
  }
}
