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
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct normalized image generation options.
pub fn ImageCallOptions::new(
  prompt : String,
  n? : Int = 1,
  size? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> ImageCallOptions {
  {
    prompt,
    n,
    size,
    headers,
    provider_options,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Result returned by an image generation call.
pub(all) struct ImageResponse {
  images : Array[GeneratedImage]
  usage : Usage
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct an image response without transport diagnostics.
pub fn ImageResponse::new(
  images : Array[GeneratedImage],
  usage : Usage,
) -> ImageResponse {
  {
    images,
    usage,
    request: None,
    response: None,
    provider_metadata: Map([]),
    warnings: [],
  }
}

///|
/// Attach diagnostics to an image result.
pub fn ImageResponse::with_diagnostics(
  self : ImageResponse,
  request : RequestMetadata?,
  response : ResponseMetadata?,
  provider_metadata : Map[String, Json],
  warnings : Array[Warning],
) -> ImageResponse {
  {
    images: self.images,
    usage: self.usage,
    request,
    response,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Add HTTP metadata to an image result.
pub fn ImageResponse::with_transport(
  self : ImageResponse,
  request : RequestMetadata,
  response : ResponseMetadata,
) -> ImageResponse {
  {
    images: self.images,
    usage: self.usage,
    request: Some(request),
    response: Some(merge_response_metadata(self.response, response)),
    provider_metadata: copy_provider_metadata(self.provider_metadata),
    warnings: copy_warnings(self.warnings),
  }
}

///|
/// Generate one or more images, splitting calls at the provider model limit.
pub async fn generate_image(
  model : &ImageModel,
  prompt : String,
  n? : Int = 1,
  size? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> ImageResponse {
  check_cancellation(cancellation_token)
  guard n > 0 else { fail("generate_image requires n to be greater than zero") }
  let max_images_per_call = model.max_images_per_call()
  guard max_images_per_call > 0 else {
    fail("image model max_images_per_call must be greater than zero")
  }
  let images : Array[GeneratedImage] = []
  let mut usage = Usage::zero()
  let mut first_request : RequestMetadata? = None
  let mut response_metadata : ResponseMetadata? = None
  let mut provider_metadata : Map[String, Json] = Map([])
  let warnings : Array[Warning] = []
  let mut remaining = n
  while remaining > 0 {
    check_cancellation(cancellation_token)
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
        retry_policy~,
        cancellation_token?,
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
    if first_request is None {
      first_request = response.request
    }
    response_metadata = merge_optional_response_metadata(
      response_metadata,
      response.response,
    )
    provider_metadata = merge_provider_metadata(
      provider_metadata,
      response.provider_metadata,
    )
    for warning in response.warnings {
      warnings.push(warning)
    }
    remaining = remaining - batch_size
  }
  {
    images,
    usage,
    request: first_request,
    response: response_metadata,
    provider_metadata,
    warnings,
  }
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
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> ImageResponse {
  generate_image(
    model,
    prompt,
    n~,
    size?,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
}
