///|
/// High-level wrapper for a provider-owned embedding middleware contract.
struct MiddlewareEmbeddingModelV4 {
  model : &@provider.EmbeddingModelV4
  middleware : @provider.EmbeddingModelV4Middleware
  provider_id : String?
  model_id : String?
}

///|
/// Wrap one embedding model with V4 middleware.
pub fn wrap_embedding_model_v4(
  model : &@provider.EmbeddingModelV4,
  middleware : @provider.EmbeddingModelV4Middleware,
  model_id? : String,
  provider_id? : String,
) -> &@provider.EmbeddingModelV4 {
  MiddlewareEmbeddingModelV4::{ model, middleware, provider_id, model_id }
  as &@provider.EmbeddingModelV4
}

///|
/// Wrap an embedding model with V4 middleware in AI SDK order.
pub fn wrap_embedding_model_v4_chain(
  model : &@provider.EmbeddingModelV4,
  middlewares : Array[@provider.EmbeddingModelV4Middleware],
  model_id? : String,
  provider_id? : String,
) -> &@provider.EmbeddingModelV4 {
  let mut wrapped = model
  let mut index = middlewares.length() - 1
  while index >= 0 {
    wrapped = wrap_embedding_model_v4(
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
/// AI SDK-style spelling for `wrap_embedding_model_v4`.
pub fn wrapEmbeddingModel(
  model : &@provider.EmbeddingModelV4,
  middleware : @provider.EmbeddingModelV4Middleware,
  model_id? : String,
  provider_id? : String,
) -> &@provider.EmbeddingModelV4 {
  wrap_embedding_model_v4(model, middleware, model_id?, provider_id?)
}

///|
/// AI SDK-style spelling for `wrap_embedding_model_v4_chain`.
pub fn wrapEmbeddingModelChain(
  model : &@provider.EmbeddingModelV4,
  middlewares : Array[@provider.EmbeddingModelV4Middleware],
  model_id? : String,
  provider_id? : String,
) -> &@provider.EmbeddingModelV4 {
  wrap_embedding_model_v4_chain(model, middlewares, model_id?, provider_id?)
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
pub impl @provider.EmbeddingModelV4 for MiddlewareEmbeddingModelV4 with fn model_id(
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
  let context = @provider.EmbeddingModelV4MiddlewareContext::{
    params: transformed,
    model: self.model,
    do_embed,
  }
  match self.middleware.wrap_embed {
    Some(wrap) => wrap(context)
    None => do_embed()
  }
}
