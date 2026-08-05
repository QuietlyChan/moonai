///|
fn decode_generated_image(json : Json) -> @provider.GeneratedImage raise {
  let data = match json {
    { "b64_json": String(value), .. } => @provider.ImageData::Base64(value)
    { "url": String(value), .. } => @provider.ImageData::Url(value)
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI-compatible image item has no b64_json or url",
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
fn image_usage_from_json(json : Json) -> @provider.Usage {
  {
    input_tokens: @provider_utils.json_int_field(json, "input_tokens"),
    output_tokens: @provider_utils.json_int_field(json, "output_tokens"),
    total_tokens: @provider_utils.json_int_field(json, "total_tokens"),
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  }
}

///|
/// Decode one OpenAI-compatible image generation response.
pub fn decode_image_response(
  json : Json,
  error_structure? : OpenAICompatibleErrorStructure = default_openai_compatible_error_structure(),
) -> @provider.ImageResponse raise {
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
    { "usage": value, .. } if !(value is Null) => image_usage_from_json(value)
    _ => @provider.Usage::zero()
  }
  @provider.ImageResponse::new(images, usage)
}
