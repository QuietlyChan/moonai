///|
fn image_response_error_message(json : Json) -> String? {
  match json {
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "error": String(message), .. } => Some(message)
    _ => None
  }
}

///|
fn decode_generated_image(json : Json) -> @moonai.GeneratedImage raise {
  let data = match json {
    { "b64_json": String(value), .. } => @moonai.ImageData::Base64(value)
    { "url": String(value), .. } => @moonai.ImageData::Url(value)
    _ => fail("OpenAI-compatible image item has no b64_json or url")
  }
  let revised_prompt = match json {
    { "revised_prompt": String(value), .. } => Some(value)
    _ => None
  }
  @moonai.GeneratedImage::new(data, revised_prompt?)
}

///|
fn image_usage_from_json(json : Json) -> @moonai.Usage {
  {
    input_tokens: @provider_utils.json_int_field(json, "input_tokens"),
    output_tokens: @provider_utils.json_int_field(json, "output_tokens"),
    total_tokens: @provider_utils.json_int_field(json, "total_tokens"),
    reasoning_tokens: 0,
    cached_input_tokens: 0,
  }
}

///|
/// Decode one OpenAI-compatible image generation response.
pub fn decode_image_response(json : Json) -> @moonai.ImageResponse raise {
  if image_response_error_message(json) is Some(message) {
    fail("OpenAI-compatible image request failed: \{message}")
  }
  let data = match json {
    { "data": Array(items), .. } => items
    _ => fail("OpenAI-compatible image response has no data")
  }
  let images : Array[@moonai.GeneratedImage] = []
  for item in data {
    images.push(decode_generated_image(item))
  }
  let usage = match json {
    { "usage": value, .. } if !(value is Null) => image_usage_from_json(value)
    _ => @moonai.Usage::zero()
  }
  { images, usage }
}
