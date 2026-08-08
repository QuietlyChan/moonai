///|
/// Context passed to an image middleware's operation wrapper.
pub(all) struct ImageModelV4MiddlewareContext {
  params : ImageModelV4CallOptions
  model : &ImageModelV4
  do_generate : async () -> ImageModelV4Result
}

///|
/// Delegate to the wrapped image model.
pub async fn ImageModelV4MiddlewareContext::generate(
  self : ImageModelV4MiddlewareContext,
) -> ImageModelV4Result {
  (self.do_generate)()
}

///|
/// Provider-level middleware contract for `ImageModelV4`.
pub(all) struct ImageModelV4Middleware {
  transform_params : (async (ImageModelV4CallOptions, &ImageModelV4) -> ImageModelV4CallOptions)?
  override_provider : ((&ImageModelV4) -> String)?
  override_model_id : ((&ImageModelV4) -> String)?
  override_max_images_per_call : ((&ImageModelV4) -> Int?)?
  wrap_generate : (async (ImageModelV4MiddlewareContext) -> ImageModelV4Result)?
}

///|
/// Construct a V4 image-model middleware contract.
pub fn ImageModelV4Middleware::new(
  transform_params? : async (ImageModelV4CallOptions, &ImageModelV4) -> ImageModelV4CallOptions,
  override_provider? : (&ImageModelV4) -> String,
  override_model_id? : (&ImageModelV4) -> String,
  override_max_images_per_call? : (&ImageModelV4) -> Int?,
  wrap_generate? : async (ImageModelV4MiddlewareContext) -> ImageModelV4Result,
) -> ImageModelV4Middleware {
  {
    transform_params,
    override_provider,
    override_model_id,
    override_max_images_per_call,
    wrap_generate,
  }
}

///|
/// Return the middleware contract version.
pub fn ImageModelV4Middleware::specification_version(
  _self : ImageModelV4Middleware,
) -> String {
  "v4"
}

///|
/// Apply the optional image parameter transform.
pub async fn ImageModelV4Middleware::transform(
  self : ImageModelV4Middleware,
  model : &ImageModelV4,
  params : ImageModelV4CallOptions,
) -> ImageModelV4CallOptions {
  match self.transform_params {
    Some(transform) => transform(params, model)
    None => params
  }
}
