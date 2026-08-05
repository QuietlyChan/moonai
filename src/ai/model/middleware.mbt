///|
/// The operation currently being transformed by chat-model middleware.
pub(all) enum ChatModelMiddlewareOperation {
  Generate
  Stream
} derive(Debug, Eq)

///|
/// Parameters and model identity visible to an asynchronous chat middleware.
///
/// The model is the model immediately inside the middleware. This mirrors AI
/// SDK's V4 middleware contract and lets a middleware inspect or delegate to
/// the wrapped model without knowing its wire protocol.
pub(all) struct ChatModelTransformContext {
  operation : ChatModelMiddlewareOperation
  params : @provider.ChatCallOptions
  model : &@provider.ChatModel
}

///|
/// Context passed to `wrap_generate` and `wrap_stream`.
pub(all) struct ChatModelMiddlewareContext {
  params : @provider.ChatCallOptions
  model : &@provider.ChatModel
  do_generate : async () -> @provider.ChatResponse
  do_stream : async () -> @provider.ChatResponse
}

///|
/// Delegate to the wrapped model's generate operation.
pub async fn ChatModelMiddlewareContext::generate(
  self : ChatModelMiddlewareContext,
) -> @provider.ChatResponse {
  (self.do_generate)()
}

///|
/// Delegate to the wrapped model's stream operation.
pub async fn ChatModelMiddlewareContext::stream(
  self : ChatModelMiddlewareContext,
) -> @provider.ChatResponse {
  (self.do_stream)()
}

///|
/// Parameter and identity overrides applied around a provider chat model.
///
/// This is the MoonBit counterpart of AI SDK's
/// `LanguageModelV4Middleware`. The synchronous callback remains convenient
/// for simple adapters; the async callback and result wrappers cover
/// middleware that needs I/O or post-processing.
pub(all) struct ChatModelMiddleware {
  transform_options : ((@provider.ChatCallOptions) -> @provider.ChatCallOptions)?
  transform_params : (async (ChatModelTransformContext) -> @provider.ChatCallOptions)?
  provider : String?
  model_id : String?
  supported_urls : Array[@provider.SupportedUrlRule]?
  override_provider : ((&@provider.ChatModel) -> String)?
  override_model_id : ((&@provider.ChatModel) -> String)?
  override_supported_urls : ((&@provider.ChatModel) -> Array[
    @provider.SupportedUrlRule,
  ])?
  wrap_generate : (async (ChatModelMiddlewareContext) -> @provider.ChatResponse)?
  wrap_stream : (async (ChatModelMiddlewareContext) -> @provider.ChatResponse)?
}

///|
/// Construct chat-model middleware.
///
/// The callback receives an isolated call-options value.  Returning the
/// original value is valid when a middleware only overrides model metadata.
pub fn ChatModelMiddleware::new(
  transform_options? : (@provider.ChatCallOptions) -> @provider.ChatCallOptions,
  provider? : String,
  model_id? : String,
  supported_urls? : Array[@provider.SupportedUrlRule],
  transform_params? : async (ChatModelTransformContext) -> @provider.ChatCallOptions,
  override_provider? : (&@provider.ChatModel) -> String,
  override_model_id? : (&@provider.ChatModel) -> String,
  override_supported_urls? : (&@provider.ChatModel) -> Array[
    @provider.SupportedUrlRule,
  ],
  wrap_generate? : async (ChatModelMiddlewareContext) -> @provider.ChatResponse,
  wrap_stream? : async (ChatModelMiddlewareContext) -> @provider.ChatResponse,
) -> ChatModelMiddleware {
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
/// Return the options after applying the optional middleware transform.
pub fn ChatModelMiddleware::apply_options(
  self : ChatModelMiddleware,
  options : @provider.ChatCallOptions,
) -> @provider.ChatCallOptions {
  match self.transform_options {
    Some(transform) => transform(options)
    None => options
  }
}

///|
/// Apply synchronous and asynchronous parameter transforms in declaration
/// order. The asynchronous callback receives the model inside this wrapper so
/// a middleware chain has the same visibility as AI SDK's nested wrappers.
pub async fn ChatModelMiddleware::transform(
  self : ChatModelMiddleware,
  operation : ChatModelMiddlewareOperation,
  model : &@provider.ChatModel,
  options : @provider.ChatCallOptions,
) -> @provider.ChatCallOptions {
  let transformed = self.apply_options(options)
  match self.transform_params {
    Some(transform) => transform({ operation, params: transformed, model })
    None => transformed
  }
}

///|
/// A provider-neutral chat model wrapper created by `wrap_chat_model`.
struct MiddlewareChatModel {
  model : &@provider.ChatModel
  middleware : ChatModelMiddleware
}

///|
/// Wrap a chat model with parameter and identity middleware.
///
/// The returned reference owns the wrapper for the duration of the returned
/// trait value.  Middleware values are immutable, so the same wrapper can be
/// reused by a registry or by multiple high-level calls.
pub fn wrap_chat_model(
  model : &@provider.ChatModel,
  middleware : ChatModelMiddleware,
) -> &@provider.ChatModel {
  MiddlewareChatModel::{ model, middleware } as &@provider.ChatModel
}

///|
/// Wrap a chat model with middleware in AI SDK order.
///
/// The first middleware in `middlewares` is the outermost wrapper and its
/// parameter transform runs first. An empty array returns the original model.
pub fn wrap_chat_model_chain(
  model : &@provider.ChatModel,
  middlewares : Array[ChatModelMiddleware],
) -> &@provider.ChatModel {
  let mut wrapped = model
  let mut index = middlewares.length() - 1
  while index >= 0 {
    wrapped = wrap_chat_model(wrapped, middlewares[index])
    index = index - 1
  }
  wrapped
}

///|
/// AI SDK-style camel-case spelling for `wrap_chat_model_chain`.
pub fn wrapChatModelChain(
  model : &@provider.ChatModel,
  middlewares : Array[ChatModelMiddleware],
) -> &@provider.ChatModel {
  wrap_chat_model_chain(model, middlewares)
}

///|
/// AI SDK-style camel-case spelling for `wrap_chat_model`.
pub fn wrapChatModel(
  model : &@provider.ChatModel,
  middleware : ChatModelMiddleware,
) -> &@provider.ChatModel {
  wrap_chat_model(model, middleware)
}

///|
pub impl @provider.ChatModel for MiddlewareChatModel with fn provider(self) -> String {
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
pub impl @provider.ChatModel for MiddlewareChatModel with fn model_id(self) -> String {
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
pub impl @provider.ChatModel for MiddlewareChatModel with fn supported_urls(
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
pub impl @provider.ChatModel for MiddlewareChatModel with fn generate(
  self,
  options,
) -> @provider.ChatResponse {
  let transformed = self.middleware.transform(Generate, self.model, options)
  let do_generate : async () -> @provider.ChatResponse = () => {
    self.model.generate(transformed)
  }
  let do_stream : async () -> @provider.ChatResponse = () => {
    self.model.stream(transformed, _ => ())
  }
  let context = ChatModelMiddlewareContext::{
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
pub impl @provider.ChatModel for MiddlewareChatModel with fn stream(
  self,
  options,
  on_event,
) -> @provider.ChatResponse {
  let transformed = self.middleware.transform(Stream, self.model, options)
  let do_generate : async () -> @provider.ChatResponse = () => {
    self.model.generate(transformed)
  }
  let do_stream : async () -> @provider.ChatResponse = () => {
    self.model.stream(transformed, on_event)
  }
  let context = ChatModelMiddlewareContext::{
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

///|
/// Context passed to wire-image `wrap_generate` middleware.
pub(all) struct ImageWireModelMiddlewareContext {
  params : @provider.ImageCallOptions
  model : &@provider.ImageWireModel
  do_generate : async () -> @provider.ImageResponse
}

///|
/// Delegate to the wrapped image model's generate operation.
pub async fn ImageWireModelMiddlewareContext::generate(
  self : ImageWireModelMiddlewareContext,
) -> @provider.ImageResponse {
  (self.do_generate)()
}

///|
/// Parameter and identity overrides applied around a wire image model.
///
/// AI SDK exposes image middleware separately from language-model middleware
/// because image calls have a different parameter and result contract.
pub(all) struct ImageWireModelMiddleware {
  transform_options : ((@provider.ImageCallOptions) -> @provider.ImageCallOptions)?
  transform_params : (async (
    @provider.ImageCallOptions,
    &@provider.ImageWireModel,
  ) -> @provider.ImageCallOptions)?
  provider : String?
  model_id : String?
  max_images_per_call : Int?
  override_provider : ((&@provider.ImageWireModel) -> String)?
  override_model_id : ((&@provider.ImageWireModel) -> String)?
  override_max_images_per_call : ((&@provider.ImageWireModel) -> Int)?
  wrap_generate : (async (ImageWireModelMiddlewareContext) -> @provider.ImageResponse)?
}

///|
/// Construct image-model middleware.
pub fn ImageWireModelMiddleware::new(
  transform_options? : (@provider.ImageCallOptions) -> @provider.ImageCallOptions,
  provider? : String,
  model_id? : String,
  max_images_per_call? : Int,
  transform_params? : async (
    @provider.ImageCallOptions,
    &@provider.ImageWireModel,
  ) -> @provider.ImageCallOptions,
  override_provider? : (&@provider.ImageWireModel) -> String,
  override_model_id? : (&@provider.ImageWireModel) -> String,
  override_max_images_per_call? : (&@provider.ImageWireModel) -> Int,
  wrap_generate? : async (ImageWireModelMiddlewareContext) -> @provider.ImageResponse,
) -> ImageWireModelMiddleware {
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
/// Return image options after applying the optional middleware transform.
pub fn ImageWireModelMiddleware::apply_options(
  self : ImageWireModelMiddleware,
  options : @provider.ImageCallOptions,
) -> @provider.ImageCallOptions {
  match self.transform_options {
    Some(transform) => transform(options)
    None => options
  }
}

///|
/// Apply image parameter transforms in declaration order.
pub async fn ImageWireModelMiddleware::transform(
  self : ImageWireModelMiddleware,
  model : &@provider.ImageWireModel,
  options : @provider.ImageCallOptions,
) -> @provider.ImageCallOptions {
  let transformed = self.apply_options(options)
  match self.transform_params {
    Some(transform) => transform(transformed, model)
    None => transformed
  }
}

///|
/// A wire image model wrapper created by `wrap_image_wire_model`.
struct MiddlewareImageWireModel {
  model : &@provider.ImageWireModel
  middleware : ImageWireModelMiddleware
}

///|
/// Wrap an image model with parameter and identity middleware.
pub fn wrap_image_wire_model(
  model : &@provider.ImageWireModel,
  middleware : ImageWireModelMiddleware,
) -> &@provider.ImageWireModel {
  MiddlewareImageWireModel::{ model, middleware } as &@provider.ImageWireModel
}

///|
/// Wrap an image model with middleware in AI SDK order.
pub fn wrap_image_wire_model_chain(
  model : &@provider.ImageWireModel,
  middlewares : Array[ImageWireModelMiddleware],
) -> &@provider.ImageWireModel {
  let mut wrapped = model
  let mut index = middlewares.length() - 1
  while index >= 0 {
    wrapped = wrap_image_wire_model(wrapped, middlewares[index])
    index = index - 1
  }
  wrapped
}

///|
/// Camel-case spelling for `wrap_image_wire_model_chain`.
pub fn wrapImageWireModelChain(
  model : &@provider.ImageWireModel,
  middlewares : Array[ImageWireModelMiddleware],
) -> &@provider.ImageWireModel {
  wrap_image_wire_model_chain(model, middlewares)
}

///|
/// Camel-case spelling for `wrap_image_wire_model`.
pub fn wrapImageWireModel(
  model : &@provider.ImageWireModel,
  middleware : ImageWireModelMiddleware,
) -> &@provider.ImageWireModel {
  wrap_image_wire_model(model, middleware)
}

///|
pub impl @provider.ImageWireModel for MiddlewareImageWireModel with fn provider(
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
pub impl @provider.ImageWireModel for MiddlewareImageWireModel with fn model_id(
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
pub impl @provider.ImageWireModel for MiddlewareImageWireModel with fn max_images_per_call(
  self,
) -> Int {
  match self.middleware.max_images_per_call {
    Some(value) => value
    None =>
      match self.middleware.override_max_images_per_call {
        Some(resolve) => resolve(self.model)
        None => self.model.max_images_per_call()
      }
  }
}

///|
pub impl @provider.ImageWireModel for MiddlewareImageWireModel with fn generate(
  self,
  options,
) -> @provider.ImageResponse {
  let transformed = self.middleware.transform(self.model, options)
  let do_generate : async () -> @provider.ImageResponse = () => {
    self.model.generate(transformed)
  }
  let context = ImageWireModelMiddlewareContext::{
    params: transformed,
    model: self.model,
    do_generate,
  }
  match self.middleware.wrap_generate {
    Some(wrap) => wrap(context)
    None => do_generate()
  }
}
