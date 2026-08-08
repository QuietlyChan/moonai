///|
/// High-level wrapper for a provider-owned image middleware contract.
struct MiddlewareImageModelV4 {
  model : &@provider.ImageModelV4
  middleware : @provider.ImageModelV4Middleware
  provider_id : String?
  model_id : String?
}

///|
/// Wrap one image model with V4 middleware.
pub fn wrap_image_model_v4(
  model : &@provider.ImageModelV4,
  middleware : @provider.ImageModelV4Middleware,
  model_id? : String,
  provider_id? : String,
) -> &@provider.ImageModelV4 {
  MiddlewareImageModelV4::{ model, middleware, provider_id, model_id }
  as &@provider.ImageModelV4
}

///|
/// Wrap an image model with V4 middleware in AI SDK order.
pub fn wrap_image_model_v4_chain(
  model : &@provider.ImageModelV4,
  middlewares : Array[@provider.ImageModelV4Middleware],
  model_id? : String,
  provider_id? : String,
) -> &@provider.ImageModelV4 {
  let mut wrapped = model
  let mut index = middlewares.length() - 1
  while index >= 0 {
    wrapped = wrap_image_model_v4(
      wrapped,
      middlewares[index],
      model_id?,
      provider_id?,
    )
    index = index - 1
  }
  wrapped
}

///|
/// AI SDK-style spelling for `wrap_image_model_v4`.
pub fn wrapImageModel(
  model : &@provider.ImageModelV4,
  middleware : @provider.ImageModelV4Middleware,
  model_id? : String,
  provider_id? : String,
) -> &@provider.ImageModelV4 {
  wrap_image_model_v4(model, middleware, model_id?, provider_id?)
}

///|
/// AI SDK-style spelling for `wrap_image_model_v4_chain`.
pub fn wrapImageModelChain(
  model : &@provider.ImageModelV4,
  middlewares : Array[@provider.ImageModelV4Middleware],
  model_id? : String,
  provider_id? : String,
) -> &@provider.ImageModelV4 {
  wrap_image_model_v4_chain(model, middlewares, model_id?, provider_id?)
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
  match self.provider_id {
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
  match self.model_id {
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
  match self.middleware.override_max_images_per_call {
    Some(resolve) => resolve(self.model)
    None => self.model.max_images_per_call()
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
  let context = @provider.ImageModelV4MiddlewareContext::{
    params: transformed,
    model: self.model,
    do_generate,
  }
  match self.middleware.wrap_generate {
    Some(wrap) => wrap(context)
    None => do_generate()
  }
}
