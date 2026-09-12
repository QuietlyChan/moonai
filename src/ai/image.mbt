///|
/// Generate one or more images, splitting calls at the provider model limit.
pub async fn generate_image(
  model : &@provider.ImageModelV4,
  prompt : String,
  n? : Int = 1,
  max_images_per_call? : Int,
  size? : String,
  aspect_ratio? : String,
  seed? : Int,
  files? : Array[@provider.ImageModelV4File] = [],
  mask? : @provider.ImageModelV4File,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> ImageResponse {
  check_cancellation(cancellation_token)
  guard n > 0 else { fail("generate_image requires n to be greater than zero") }
  let max_images_per_call = match max_images_per_call {
    Some(value) => value
    None => model.max_images_per_call().unwrap_or(1)
  }
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
    // Transient empty results are retried within the retry scope so a
    // single blank response does not fail the whole generation.
    let mut retry_number = 0
    let mut delay = @provider_utils.initial_retry_delay(retry_policy)
    let mut completed : ImageResponse? = None
    while completed is None {
      check_cancellation(cancellation_token)
      let response = model
        .do_generate(
          @provider.ImageModelV4CallOptions::new(
            prompt~,
            n=batch_size,
            size?,
            aspect_ratio?,
            seed?,
            files~,
            mask?,
            headers~,
            provider_options~,
            retry_policy~,
            cancellation_token?,
          ),
        )
        .to_image_response()
      if response.images.length() == batch_size {
        completed = Some(response)
      } else if retry_policy.can_retry(retry_number) {
        @provider_utils.sleep_with_cancellation(delay, cancellation_token)
        delay = @provider_utils.next_retry_delay(retry_policy, delay)
        retry_number = retry_number + 1
      } else {
        fail(
          "image provider returned \{response.images.length()} images for a batch of \{batch_size} after \{retry_number + 1} attempts",
        )
      }
    }
    let response = completed.unwrap()
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
/// AI SDK-style camel-case spelling for `generate_image`.
pub async fn generateImage(
  model : &@provider.ImageModelV4,
  prompt : String,
  n? : Int = 1,
  max_images_per_call? : Int,
  size? : String,
  aspect_ratio? : String,
  seed? : Int,
  files? : Array[@provider.ImageModelV4File] = [],
  mask? : @provider.ImageModelV4File,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> ImageResponse {
  generate_image(
    model,
    prompt,
    n~,
    max_images_per_call?,
    size?,
    aspect_ratio?,
    seed?,
    files~,
    mask?,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
}
