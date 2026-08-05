///|
/// Parameters and model identity visible to an image V4 middleware wrapper.
pub(all) struct ImageModelV4MiddlewareContext {
  params : @provider.ImageModelV4CallOptions
  model : &@provider.ImageModelV4
  do_generate : async () -> @provider.ImageModelV4Result
}

///|
/// Delegate to the wrapped V4 image model.
pub async fn ImageModelV4MiddlewareContext::generate(
  self : ImageModelV4MiddlewareContext,
) -> @provider.ImageModelV4Result {
  (self.do_generate)()
}

///|
/// Middleware for the AI SDK-aligned image model contract.
pub(all) struct ImageModelV4Middleware {
  transform_options : ((@provider.ImageModelV4CallOptions) -> @provider.ImageModelV4CallOptions)?
  transform_params : (async (
    @provider.ImageModelV4CallOptions,
    &@provider.ImageModelV4,
  ) -> @provider.ImageModelV4CallOptions)?
  provider : String?
  model_id : String?
  max_images_per_call : Int?
  override_provider : ((&@provider.ImageModelV4) -> String)?
  override_model_id : ((&@provider.ImageModelV4) -> String)?
  override_max_images_per_call : ((&@provider.ImageModelV4) -> Int?)?
  wrap_generate : (async (ImageModelV4MiddlewareContext) -> @provider.ImageModelV4Result)?
}

///|
/// Construct V4 image-model middleware.
pub fn ImageModelV4Middleware::new(
  transform_options? : (@provider.ImageModelV4CallOptions) -> @provider.ImageModelV4CallOptions,
  provider? : String,
  model_id? : String,
  max_images_per_call? : Int,
  transform_params? : async (
    @provider.ImageModelV4CallOptions,
    &@provider.ImageModelV4,
  ) -> @provider.ImageModelV4CallOptions,
  override_provider? : (&@provider.ImageModelV4) -> String,
  override_model_id? : (&@provider.ImageModelV4) -> String,
  override_max_images_per_call? : (&@provider.ImageModelV4) -> Int?,
  wrap_generate? : async (ImageModelV4MiddlewareContext) -> @provider.ImageModelV4Result,
) -> ImageModelV4Middleware {
  {
    transform_options,
    transform_params,
    provider,
    model_id,
    max_images_per_call,
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
/// Apply a synchronous V4 image option transform.
pub fn ImageModelV4Middleware::apply_options(
  self : ImageModelV4Middleware,
  options : @provider.ImageModelV4CallOptions,
) -> @provider.ImageModelV4CallOptions {
  match self.transform_options {
    Some(transform) => transform(options)
    None => options
  }
}

///|
/// Apply all V4 image parameter transforms in declaration order.
pub async fn ImageModelV4Middleware::transform(
  self : ImageModelV4Middleware,
  model : &@provider.ImageModelV4,
  options : @provider.ImageModelV4CallOptions,
) -> @provider.ImageModelV4CallOptions {
  let transformed = self.apply_options(options)
  match self.transform_params {
    Some(transform) => transform(transformed, model)
    None => transformed
  }
}

///|
struct MiddlewareImageModelV4 {
  model : &@provider.ImageModelV4
  middleware : ImageModelV4Middleware
}

///|
/// Wrap one image model with V4 middleware.
pub fn wrap_image_model_v4(
  model : &@provider.ImageModelV4,
  middleware : ImageModelV4Middleware,
) -> &@provider.ImageModelV4 {
  MiddlewareImageModelV4::{ model, middleware } as &@provider.ImageModelV4
}

///|
/// Wrap an image model with V4 middleware in AI SDK order.
pub fn wrap_image_model_v4_chain(
  model : &@provider.ImageModelV4,
  middlewares : Array[ImageModelV4Middleware],
) -> &@provider.ImageModelV4 {
  let mut wrapped = model
  let mut index = middlewares.length() - 1
  while index >= 0 {
    wrapped = wrap_image_model_v4(wrapped, middlewares[index])
    index = index - 1
  }
  wrapped
}

///|
/// AI SDK-style spelling for `wrap_image_model_v4`.
pub fn wrapImageModel(
  model : &@provider.ImageModelV4,
  middleware : ImageModelV4Middleware,
) -> &@provider.ImageModelV4 {
  wrap_image_model_v4(model, middleware)
}

///|
/// AI SDK-style spelling for `wrap_image_model_v4_chain`.
pub fn wrapImageModelChain(
  model : &@provider.ImageModelV4,
  middlewares : Array[ImageModelV4Middleware],
) -> &@provider.ImageModelV4 {
  wrap_image_model_v4_chain(model, middlewares)
}

///|
pub impl @provider.ImageModelV4 for MiddlewareImageModelV4 with fn specification_version(
  self,
) -> String {
  self.model.specification_version()
}

///|
pub impl @provider.ImageModelV4 for MiddlewareImageModelV4 with fn provider(
  self,
) -> String {
  match self.middleware.provider {
    Some(value) => value
    None =>
      match self.middleware.override_provider {
        Some(resolve) => resolve(self.model)
        None => self.model.provider()
      }
  }
}

///|
pub impl @provider.ImageModelV4 for MiddlewareImageModelV4 with fn model_id(
  self,
) -> String {
  match self.middleware.model_id {
    Some(value) => value
    None =>
      match self.middleware.override_model_id {
        Some(resolve) => resolve(self.model)
        None => self.model.model_id()
      }
  }
}

///|
pub impl @provider.ImageModelV4 for MiddlewareImageModelV4 with fn max_images_per_call(
  self,
) -> Int? {
  match self.middleware.max_images_per_call {
    Some(value) => Some(value)
    None =>
      match self.middleware.override_max_images_per_call {
        Some(resolve) => resolve(self.model)
        None => self.model.max_images_per_call()
      }
  }
}

///|
pub impl @provider.ImageModelV4 for MiddlewareImageModelV4 with fn do_generate(
  self,
  options,
) {
  let transformed = self.middleware.transform(self.model, options)
  let do_generate : async () -> @provider.ImageModelV4Result = () => {
    self.model.do_generate(transformed)
  }
  let context = ImageModelV4MiddlewareContext::{
    params: transformed,
    model: self.model,
    do_generate,
  }
  match self.middleware.wrap_generate {
    Some(wrap) => wrap(context)
    None => do_generate()
  }
}
