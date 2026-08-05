///|
/// The operation currently being transformed by V4 language-model middleware.
pub(all) enum LanguageModelV4MiddlewareOperation {
  Generate
  Stream
} derive(Debug, Eq)

///|
/// Parameters and model identity visible to an asynchronous V4 middleware.
pub(all) struct LanguageModelV4TransformContext {
  operation : LanguageModelV4MiddlewareOperation
  params : @provider.LanguageModelV4CallOptions
  model : &@provider.LanguageModelV4
}

///|
/// Context passed to V4 `wrap_generate` and `wrap_stream` callbacks.
pub(all) struct LanguageModelV4MiddlewareContext {
  params : @provider.LanguageModelV4CallOptions
  model : &@provider.LanguageModelV4
  do_generate : async () -> @provider.LanguageModelV4GenerateResult
  do_stream : async () -> @provider.LanguageModelV4StreamResult
}

///|
/// Delegate to the wrapped V4 model's generate operation.
pub async fn LanguageModelV4MiddlewareContext::generate(
  self : LanguageModelV4MiddlewareContext,
) -> @provider.LanguageModelV4GenerateResult {
  (self.do_generate)()
}

///|
/// Delegate to the wrapped V4 model's stream operation.
pub async fn LanguageModelV4MiddlewareContext::stream(
  self : LanguageModelV4MiddlewareContext,
) -> @provider.LanguageModelV4StreamResult {
  (self.do_stream)()
}

///|
/// Parameter, identity, and result middleware for `LanguageModelV4`.
///
/// This mirrors AI SDK's `LanguageModelV4Middleware`. The synchronous option
/// transform is useful for small adapters; the asynchronous transform and
/// result wrappers support middleware that needs I/O or post-processing.
pub(all) struct LanguageModelV4Middleware {
  transform_options : ((@provider.LanguageModelV4CallOptions) -> @provider.LanguageModelV4CallOptions)?
  transform_params : (async (LanguageModelV4TransformContext) -> @provider.LanguageModelV4CallOptions)?
  provider : String?
  model_id : String?
  supported_urls : Array[@provider.SupportedUrlRule]?
  override_provider : ((&@provider.LanguageModelV4) -> String)?
  override_model_id : ((&@provider.LanguageModelV4) -> String)?
  override_supported_urls : ((&@provider.LanguageModelV4) -> Array[
    @provider.SupportedUrlRule,
  ])?
  wrap_generate : (async (LanguageModelV4MiddlewareContext) -> @provider.LanguageModelV4GenerateResult)?
  wrap_stream : (async (LanguageModelV4MiddlewareContext) -> @provider.LanguageModelV4StreamResult)?
}

///|
/// Construct V4 language-model middleware.
pub fn LanguageModelV4Middleware::new(
  transform_options? : (@provider.LanguageModelV4CallOptions) -> @provider.LanguageModelV4CallOptions,
  provider? : String,
  model_id? : String,
  supported_urls? : Array[@provider.SupportedUrlRule],
  transform_params? : async (LanguageModelV4TransformContext) -> @provider.LanguageModelV4CallOptions,
  override_provider? : (&@provider.LanguageModelV4) -> String,
  override_model_id? : (&@provider.LanguageModelV4) -> String,
  override_supported_urls? : (&@provider.LanguageModelV4) -> Array[
    @provider.SupportedUrlRule,
  ],
  wrap_generate? : async (LanguageModelV4MiddlewareContext) -> @provider.LanguageModelV4GenerateResult,
  wrap_stream? : async (LanguageModelV4MiddlewareContext) -> @provider.LanguageModelV4StreamResult,
) -> LanguageModelV4Middleware {
  {
    transform_options,
    transform_params,
    provider,
    model_id,
    supported_urls: supported_urls.map(values => values.copy()),
    override_provider,
    override_model_id,
    override_supported_urls,
    wrap_generate,
    wrap_stream,
  }
}

///|
/// Return the middleware contract version.
pub fn LanguageModelV4Middleware::specification_version(
  _self : LanguageModelV4Middleware,
) -> String {
  "v4"
}

///|
/// Return the options after applying the optional synchronous transform.
pub fn LanguageModelV4Middleware::apply_options(
  self : LanguageModelV4Middleware,
  options : @provider.LanguageModelV4CallOptions,
) -> @provider.LanguageModelV4CallOptions {
  match self.transform_options {
    Some(transform) => transform(options)
    None => options
  }
}

///|
/// Apply synchronous and asynchronous parameter transforms in declaration
/// order.
pub async fn LanguageModelV4Middleware::transform(
  self : LanguageModelV4Middleware,
  operation : LanguageModelV4MiddlewareOperation,
  model : &@provider.LanguageModelV4,
  options : @provider.LanguageModelV4CallOptions,
) -> @provider.LanguageModelV4CallOptions {
  let transformed = self.apply_options(options)
  match self.transform_params {
    Some(transform) => transform({ operation, params: transformed, model })
    None => transformed
  }
}

///|
/// A provider-neutral V4 language-model wrapper.
struct MiddlewareLanguageModelV4 {
  model : &@provider.LanguageModelV4
  middleware : LanguageModelV4Middleware
}

///|
/// Wrap a V4 language model with parameter, identity, and result middleware.
pub fn wrap_language_model_v4(
  model : &@provider.LanguageModelV4,
  middleware : LanguageModelV4Middleware,
) -> &@provider.LanguageModelV4 {
  MiddlewareLanguageModelV4::{ model, middleware } as &@provider.LanguageModelV4
}

///|
/// Wrap a V4 language model with middleware in AI SDK order.
///
/// The first middleware is the outermost wrapper and its parameter transform
/// runs first. An empty array returns the original model.
pub fn wrap_language_model_v4_chain(
  model : &@provider.LanguageModelV4,
  middlewares : Array[LanguageModelV4Middleware],
) -> &@provider.LanguageModelV4 {
  let mut wrapped = model
  let mut index = middlewares.length() - 1
  while index >= 0 {
    wrapped = wrap_language_model_v4(wrapped, middlewares[index])
    index = index - 1
  }
  wrapped
}

///|
/// AI SDK-style camel-case spelling for `wrap_language_model_v4`.
pub fn wrapLanguageModelV4(
  model : &@provider.LanguageModelV4,
  middleware : LanguageModelV4Middleware,
) -> &@provider.LanguageModelV4 {
  wrap_language_model_v4(model, middleware)
}

///|
/// AI SDK-style camel-case spelling for `wrap_language_model_v4_chain`.
pub fn wrapLanguageModelV4Chain(
  model : &@provider.LanguageModelV4,
  middlewares : Array[LanguageModelV4Middleware],
) -> &@provider.LanguageModelV4 {
  wrap_language_model_v4_chain(model, middlewares)
}

///|
/// AI SDK-style spelling for `wrap_language_model_v4`.
pub fn wrapLanguageModel(
  model : &@provider.LanguageModelV4,
  middleware : LanguageModelV4Middleware,
) -> &@provider.LanguageModelV4 {
  wrap_language_model_v4(model, middleware)
}

///|
/// AI SDK-style spelling for `wrap_language_model_v4_chain`.
pub fn wrapLanguageModelChain(
  model : &@provider.LanguageModelV4,
  middlewares : Array[LanguageModelV4Middleware],
) -> &@provider.LanguageModelV4 {
  wrap_language_model_v4_chain(model, middlewares)
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
pub impl @provider.LanguageModelV4 for MiddlewareLanguageModelV4 with fn model_id(
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
pub impl @provider.LanguageModelV4 for MiddlewareLanguageModelV4 with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  match self.middleware.supported_urls {
    Some(values) => values.copy()
    None =>
      match self.middleware.override_supported_urls {
        Some(resolve) => resolve(self.model)
        None => self.model.supported_urls()
      }
  }
}

///|
pub impl @provider.LanguageModelV4 for MiddlewareLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let transformed = self.middleware.transform(Generate, self.model, options)
  let do_generate : async () -> @provider.LanguageModelV4GenerateResult = () => {
    self.model.do_generate(transformed)
  }
  let do_stream : async () -> @provider.LanguageModelV4StreamResult = () => {
    self.model.do_stream(transformed, _ => ())
  }
  let context = LanguageModelV4MiddlewareContext::{
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
  let transformed = self.middleware.transform(Stream, self.model, options)
  let do_generate : async () -> @provider.LanguageModelV4GenerateResult = () => {
    self.model.do_generate(transformed)
  }
  let do_stream : async () -> @provider.LanguageModelV4StreamResult = () => {
    self.model.do_stream(transformed, on_event)
  }
  let context = LanguageModelV4MiddlewareContext::{
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
