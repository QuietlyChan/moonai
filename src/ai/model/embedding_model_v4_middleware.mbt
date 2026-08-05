///|
/// Context passed to an embedding V4 middleware's `wrap_embed` callback.
pub(all) struct EmbeddingModelV4MiddlewareContext {
  params : @provider.EmbeddingModelV4CallOptions
  model : &@provider.EmbeddingModelV4
  do_embed : async () -> @provider.EmbeddingModelV4Result
}

///|
/// Delegate to the wrapped V4 embedding model.
pub async fn EmbeddingModelV4MiddlewareContext::embed(
  self : EmbeddingModelV4MiddlewareContext,
) -> @provider.EmbeddingModelV4Result {
  (self.do_embed)()
}

///|
/// Middleware for the AI SDK-aligned embedding model contract.
pub(all) struct EmbeddingModelV4Middleware {
  transform_params : (async (
    @provider.EmbeddingModelV4CallOptions,
    &@provider.EmbeddingModelV4,
  ) -> @provider.EmbeddingModelV4CallOptions)?
  override_provider : ((&@provider.EmbeddingModelV4) -> String)?
  override_model_id : ((&@provider.EmbeddingModelV4) -> String)?
  override_max_embeddings_per_call : ((&@provider.EmbeddingModelV4) -> Int?)?
  override_supports_parallel_calls : ((&@provider.EmbeddingModelV4) -> Bool)?
  wrap_embed : (async (EmbeddingModelV4MiddlewareContext) -> @provider.EmbeddingModelV4Result)?
}

///|
/// Construct V4 embedding-model middleware.
pub fn EmbeddingModelV4Middleware::new(
  transform_params? : async (
    @provider.EmbeddingModelV4CallOptions,
    &@provider.EmbeddingModelV4,
  ) -> @provider.EmbeddingModelV4CallOptions,
  override_provider? : (&@provider.EmbeddingModelV4) -> String,
  override_model_id? : (&@provider.EmbeddingModelV4) -> String,
  override_max_embeddings_per_call? : (&@provider.EmbeddingModelV4) -> Int?,
  override_supports_parallel_calls? : (&@provider.EmbeddingModelV4) -> Bool,
  wrap_embed? : async (EmbeddingModelV4MiddlewareContext) -> @provider.EmbeddingModelV4Result,
) -> EmbeddingModelV4Middleware {
  {
    transform_params,
    override_provider,
    override_model_id,
    override_max_embeddings_per_call,
    override_supports_parallel_calls,
    wrap_embed,
  }
}

///|
/// Return the middleware contract version.
pub fn EmbeddingModelV4Middleware::specification_version(
  _self : EmbeddingModelV4Middleware,
) -> String {
  "v4"
}

///|
/// Apply the optional asynchronous parameter transform.
pub async fn EmbeddingModelV4Middleware::transform(
  self : EmbeddingModelV4Middleware,
  model : &@provider.EmbeddingModelV4,
  options : @provider.EmbeddingModelV4CallOptions,
) -> @provider.EmbeddingModelV4CallOptions {
  match self.transform_params {
    Some(transform) => transform(options, model)
    None => options
  }
}

///|
struct MiddlewareEmbeddingModelV4 {
  model : &@provider.EmbeddingModelV4
  middleware : EmbeddingModelV4Middleware
}

///|
/// Wrap one embedding model with V4 middleware.
pub fn wrap_embedding_model_v4(
  model : &@provider.EmbeddingModelV4,
  middleware : EmbeddingModelV4Middleware,
) -> &@provider.EmbeddingModelV4 {
  MiddlewareEmbeddingModelV4::{ model, middleware }
  as &@provider.EmbeddingModelV4
}

///|
/// Wrap an embedding model with V4 middleware in AI SDK order.
pub fn wrap_embedding_model_v4_chain(
  model : &@provider.EmbeddingModelV4,
  middlewares : Array[EmbeddingModelV4Middleware],
) -> &@provider.EmbeddingModelV4 {
  let mut wrapped = model
  let mut index = middlewares.length() - 1
  while index >= 0 {
    wrapped = wrap_embedding_model_v4(wrapped, middlewares[index])
    index = index - 1
  }
  wrapped
}

///|
/// AI SDK-style spelling for `wrap_embedding_model_v4`.
pub fn wrapEmbeddingModel(
  model : &@provider.EmbeddingModelV4,
  middleware : EmbeddingModelV4Middleware,
) -> &@provider.EmbeddingModelV4 {
  wrap_embedding_model_v4(model, middleware)
}

///|
/// AI SDK-style spelling for `wrap_embedding_model_v4_chain`.
pub fn wrapEmbeddingModelChain(
  model : &@provider.EmbeddingModelV4,
  middlewares : Array[EmbeddingModelV4Middleware],
) -> &@provider.EmbeddingModelV4 {
  wrap_embedding_model_v4_chain(model, middlewares)
}

///|
pub impl @provider.EmbeddingModelV4 for MiddlewareEmbeddingModelV4 with fn specification_version(
  self,
) -> String {
  self.model.specification_version()
}

///|
pub impl @provider.EmbeddingModelV4 for MiddlewareEmbeddingModelV4 with fn provider(
  self,
) -> String {
  match self.middleware.override_provider {
    Some(resolve) => resolve(self.model)
    None => self.model.provider()
  }
}

///|
pub impl @provider.EmbeddingModelV4 for MiddlewareEmbeddingModelV4 with fn model_id(
  self,
) -> String {
  match self.middleware.override_model_id {
    Some(resolve) => resolve(self.model)
    None => self.model.model_id()
  }
}

///|
pub impl @provider.EmbeddingModelV4 for MiddlewareEmbeddingModelV4 with fn max_embeddings_per_call(
  self,
) -> Int? {
  match self.middleware.override_max_embeddings_per_call {
    Some(resolve) => resolve(self.model)
    None => self.model.max_embeddings_per_call()
  }
}

///|
pub impl @provider.EmbeddingModelV4 for MiddlewareEmbeddingModelV4 with fn supports_parallel_calls(
  self,
) -> Bool {
  match self.middleware.override_supports_parallel_calls {
    Some(resolve) => resolve(self.model)
    None => self.model.supports_parallel_calls()
  }
}

///|
pub impl @provider.EmbeddingModelV4 for MiddlewareEmbeddingModelV4 with fn do_embed(
  self,
  options,
) {
  let transformed = self.middleware.transform(self.model, options)
  let do_embed : async () -> @provider.EmbeddingModelV4Result = () => {
    self.model.do_embed(transformed)
  }
  let context = EmbeddingModelV4MiddlewareContext::{
    params: transformed,
    model: self.model,
    do_embed,
  }
  match self.middleware.wrap_embed {
    Some(wrap) => wrap(context)
    None => do_embed()
  }
}
