///|
async fn transform_image_options(
  options : @provider.ImageModelV4CallOptions,
  _model : &@provider.ImageModelV4,
) -> @provider.ImageModelV4CallOptions {
  @async.pause()
  @provider.ImageModelV4CallOptions::new(
    prompt?=options.prompt,
    n=2,
    size?=options.size,
    aspect_ratio?=options.aspect_ratio,
    seed?=options.seed,
    files?=options.files,
    mask?=options.mask,
    headers=options.headers,
    provider_options=options.provider_options,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}

///|
async fn passthrough_image_v4_result(
  context : @provider.ImageModelV4MiddlewareContext,
) -> @provider.ImageModelV4Result {
  context.generate()
}

///|
async test "image V4 middleware overrides identity and delegates generation" {
  let base = @testing.MockImageModel::new(
    @provider.ImageResponse::new(
      [@provider.GeneratedImage::new(@provider.ImageData::Base64("image"))],
      @provider.Usage::zero(),
    ),
    max_images_per_call=3,
    provider_name="base",
    model_id="base-image",
  )
  let wrapped = wrapImageModel(
    base,
    @provider.ImageModelV4Middleware::new(
      override_max_images_per_call=_ => Some(4),
      wrap_generate=passthrough_image_v4_result,
    ),
    provider_id="wrapped",
    model_id="wrapped-image",
  )
  assert_eq(wrapped.specification_version(), "v4")
  assert_eq(wrapped.provider(), "wrapped")
  assert_eq(wrapped.model_id(), "wrapped-image")
  assert_eq(wrapped.max_images_per_call(), Some(4))
  ignore(
    wrapped.do_generate(
      @provider.ImageModelV4CallOptions::new(prompt="hello", n=1),
    ),
  )
  assert_eq(base.captured_batch_sizes(), [1])
}

///|
async test "image V4 middleware transforms options before the wire adapter" {
  let base = @testing.MockImageModel::new(
    @provider.ImageResponse::new(
      [@provider.GeneratedImage::new(@provider.ImageData::Base64("image"))],
      @provider.Usage::zero(),
    ),
  )
  let wrapped = wrap_image_model_v4_chain(base, [
    @provider.ImageModelV4Middleware::new(
      transform_params=transform_image_options,
    ),
    @provider.ImageModelV4Middleware::new(
      wrap_generate=passthrough_image_v4_result,
    ),
  ])
  ignore(
    wrapped.do_generate(
      @provider.ImageModelV4CallOptions::new(prompt="hello", n=1),
    ),
  )
  assert_eq(base.captured_batch_sizes(), [2])
}
