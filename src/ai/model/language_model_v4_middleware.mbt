///|
/// A high-level wrapper that applies a provider-owned V4 middleware contract.
struct MiddlewareLanguageModelV4 {
  model : &@provider.LanguageModelV4
  middleware : @provider.LanguageModelV4Middleware
  provider_id : String?
  model_id : String?
}

///|
/// Wrap a V4 language model with parameter, identity, and result middleware.
///
/// The middleware contract lives in `provider`; this package owns only model
/// composition, matching AI SDK's provider/ai boundary.
pub fn wrap_language_model_v4(
  model : &@provider.LanguageModelV4,
  middleware : @provider.LanguageModelV4Middleware,
  model_id? : String,
  provider_id? : String,
) -> &@provider.LanguageModelV4 {
  MiddlewareLanguageModelV4::{ model, middleware, provider_id, model_id }
  as &@provider.LanguageModelV4
}

///|
/// Wrap a V4 language model with middleware in AI SDK order.
///
/// The first middleware is the outermost wrapper and transforms input first.
pub fn wrap_language_model_v4_chain(
  model : &@provider.LanguageModelV4,
  middlewares : Array[@provider.LanguageModelV4Middleware],
  model_id? : String,
  provider_id? : String,
) -> &@provider.LanguageModelV4 {
  let mut wrapped = model
  let mut index = middlewares.length() - 1
  while index >= 0 {
    wrapped = wrap_language_model_v4(
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
/// AI SDK-style camel-case spelling for `wrap_language_model_v4`.
pub fn wrapLanguageModelV4(
  model : &@provider.LanguageModelV4,
  middleware : @provider.LanguageModelV4Middleware,
  model_id? : String,
  provider_id? : String,
) -> &@provider.LanguageModelV4 {
  wrap_language_model_v4(model, middleware, model_id?, provider_id?)
}

///|
/// AI SDK-style camel-case spelling for `wrap_language_model_v4_chain`.
pub fn wrapLanguageModelV4Chain(
  model : &@provider.LanguageModelV4,
  middlewares : Array[@provider.LanguageModelV4Middleware],
  model_id? : String,
  provider_id? : String,
) -> &@provider.LanguageModelV4 {
  wrap_language_model_v4_chain(model, middlewares, model_id?, provider_id?)
}

///|
/// AI SDK-style spelling for `wrap_language_model_v4`.
pub fn wrapLanguageModel(
  model : &@provider.LanguageModelV4,
  middleware : @provider.LanguageModelV4Middleware,
  model_id? : String,
  provider_id? : String,
) -> &@provider.LanguageModelV4 {
  wrap_language_model_v4(model, middleware, model_id?, provider_id?)
}

///|
/// AI SDK-style spelling for `wrap_language_model_v4_chain`.
pub fn wrapLanguageModelChain(
  model : &@provider.LanguageModelV4,
  middlewares : Array[@provider.LanguageModelV4Middleware],
  model_id? : String,
  provider_id? : String,
) -> &@provider.LanguageModelV4 {
  wrap_language_model_v4_chain(model, middlewares, model_id?, provider_id?)
}

///|
pub impl @provider.LanguageModelV4 for MiddlewareLanguageModelV4 with fn specification_version(
  self,
) -> String {
  self.model.specification_version()
}

///|
pub impl @provider.LanguageModelV4 for MiddlewareLanguageModelV4 with fn provider(
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
pub impl @provider.LanguageModelV4 for MiddlewareLanguageModelV4 with fn model_id(
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
pub impl @provider.LanguageModelV4 for MiddlewareLanguageModelV4 with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  match self.middleware.override_supported_urls {
    Some(resolve) => resolve(self.model)
    None => self.model.supported_urls()
  }
}

///|
pub impl @provider.LanguageModelV4 for MiddlewareLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let transformed = self.middleware.transform(
    @provider.Generate,
    self.model,
    options,
  )
  let do_generate : async () -> @provider.LanguageModelV4GenerateResult = () => {
    self.model.do_generate(transformed)
  }
  let do_stream : async () -> @provider.LanguageModelV4StreamResult = () => {
    self.model.do_stream(transformed, _ => ())
  }
  let context = @provider.LanguageModelV4MiddlewareContext::{
    params: transformed,
    model: self.model,
    do_generate,
    do_stream,
  }
  match self.middleware.wrap_generate {
    Some(wrap) => wrap(context)
    None => do_generate()
  }
}

///|
pub impl @provider.LanguageModelV4 for MiddlewareLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let transformed = self.middleware.transform(
    @provider.Stream,
    self.model,
    options,
  )
  let do_generate : async () -> @provider.LanguageModelV4GenerateResult = () => {
    self.model.do_generate(transformed)
  }
  let do_stream : async () -> @provider.LanguageModelV4StreamResult = () => {
    self.model.do_stream(transformed, on_event)
  }
  let context = @provider.LanguageModelV4MiddlewareContext::{
    params: transformed,
    model: self.model,
    do_generate,
    do_stream,
  }
  match self.middleware.wrap_stream {
    Some(wrap) => wrap(context)
    None => do_stream()
  }
}
