///|
fn encode_image_request_data(
  model_id : String,
  prompt : String?,
  n : Int,
  size : String?,
  provider_options : Map[String, Json],
  include_response_format : Bool,
) -> Json {
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ..if prompt is Some(value) {
        [("prompt", Json::string(value))]
      },
      ("n", Json::number(n.to_double())),
      ..if size is Some(value) {
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
