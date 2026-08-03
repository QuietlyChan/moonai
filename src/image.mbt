///|
/// The payload returned for a generated image.
pub(all) enum ImageData {
  Base64(String)
  Url(String)
} derive(Debug, Eq)

///|
/// One generated image and optional provider-revised prompt.
pub(all) struct GeneratedImage {
  data : ImageData
  revised_prompt : String?
} derive(Debug, Eq)

///|
/// Construct one generated image.
pub fn GeneratedImage::new(
  data : ImageData,
  revised_prompt? : String,
) -> GeneratedImage {
  { data, revised_prompt }
}

///|
/// Options passed to one provider image request.
pub(all) struct ImageCallOptions {
  prompt : String
  n : Int
  size : String?
  headers : Map[String, String]
  provider_options : Map[String, Json]
} derive(Debug)

///|
/// Construct normalized image generation options.
pub fn ImageCallOptions::new(
  prompt : String,
  n? : Int = 1,
  size? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
) -> ImageCallOptions {
  { prompt, n, size, headers, provider_options }
}

///|
/// Result returned by an image generation call.
pub(all) struct ImageResponse {
  images : Array[GeneratedImage]
  usage : Usage
} derive(Debug, Eq)

///|
/// Generate one or more images, splitting calls at the provider model limit.
pub async fn generate_image(
  model : &ImageModel,
  prompt : String,
  n? : Int = 1,
  size? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
) -> ImageResponse {
  guard n > 0 else { fail("generate_image requires n to be greater than zero") }
  let max_images_per_call = model.max_images_per_call()
  guard max_images_per_call > 0 else {
    fail("image model max_images_per_call must be greater than zero")
  }
  let images : Array[GeneratedImage] = []
  let mut usage = Usage::zero()
  let mut remaining = n
  while remaining > 0 {
    let batch_size = if remaining < max_images_per_call {
      remaining
    } else {
      max_images_per_call
    }
    let response = model.generate(
      ImageCallOptions::new(
        prompt,
        n=batch_size,
        size?,
        headers~,
        provider_options~,
      ),
    )
    guard response.images.length() == batch_size else {
      fail(
        "image provider returned \{response.images.length()} images for a batch of \{batch_size}",
      )
    }
    for image in response.images {
      images.push(image)
    }
    usage = usage.add(response.usage)
    remaining = remaining - batch_size
  }
  { images, usage }
}

///|
/// Camel-case compatibility alias for AI SDK's `generateImage`.
pub async fn generateImage(
  model : &ImageModel,
  prompt : String,
  n? : Int = 1,
  size? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
) -> ImageResponse {
  generate_image(model, prompt, n~, size?, headers~, provider_options~)
}
