///|
fn decode_generated_image(json : Json) -> @provider.GeneratedImage raise {
  let data = match json {
    { "b64_json": String(value), .. } => @provider.ImageData::Base64(value)
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI-compatible image item has no b64_json",
        data=json,
      )
  }
  let revised_prompt = match json {
    { "revised_prompt": String(value), .. } => Some(value)
    _ => None
  }
  @provider.GeneratedImage::new(data, revised_prompt?)
}

///|
fn decode_image_response_data(
  json : Json,
  error_structure : OpenAICompatibleErrorStructure,
) -> (Array[@provider.GeneratedImage], @provider.ImageModelV4Usage?) raise {
  if error_structure.message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI-compatible image request failed: \{message}",
      data=json,
    )
  }
  let data = match json {
    { "data": Array(items), .. } => items
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI-compatible image response has no data",
        data=json,
      )
  }
  let images : Array[@provider.GeneratedImage] = []
  for item in data {
    images.push(decode_generated_image(item))
  }
  let usage = match json {
    { "usage": value, .. } if !(value is Null) =>
      Some(
        @provider.ImageModelV4Usage::new(
          input_tokens=@provider_utils.json_int_field(value, "input_tokens"),
          output_tokens=@provider_utils.json_int_field(value, "output_tokens"),
          total_tokens=@provider_utils.json_int_field(value, "total_tokens"),
        ),
      )
    _ => None
  }
  (images, usage)
}
