///|
/// Context passed to an embedding middleware's operation wrapper.
pub(all) struct EmbeddingModelV4MiddlewareContext {
  params : EmbeddingModelV4CallOptions
  model : &EmbeddingModelV4
  do_embed : async () -> EmbeddingModelV4Result
}

///|
/// Delegate to the wrapped embedding model.
pub async fn EmbeddingModelV4MiddlewareContext::embed(
  self : EmbeddingModelV4MiddlewareContext,
) -> EmbeddingModelV4Result {
  (self.do_embed)()
}

///|
/// Provider-level middleware contract for `EmbeddingModelV4`.
pub(all) struct EmbeddingModelV4Middleware {
  transform_params : (async (EmbeddingModelV4CallOptions, &EmbeddingModelV4) -> EmbeddingModelV4CallOptions)?
  override_provider : ((&EmbeddingModelV4) -> String)?
  override_model_id : ((&EmbeddingModelV4) -> String)?
  override_max_embeddings_per_call : ((&EmbeddingModelV4) -> Int?)?
  override_supports_parallel_calls : ((&EmbeddingModelV4) -> Bool)?
  wrap_embed : (async (EmbeddingModelV4MiddlewareContext) -> EmbeddingModelV4Result)?
}

///|
/// Construct a V4 embedding-model middleware contract.
pub fn EmbeddingModelV4Middleware::new(
  transform_params? : async (EmbeddingModelV4CallOptions, &EmbeddingModelV4) -> EmbeddingModelV4CallOptions,
  override_provider? : (&EmbeddingModelV4) -> String,
  override_model_id? : (&EmbeddingModelV4) -> String,
  override_max_embeddings_per_call? : (&EmbeddingModelV4) -> Int?,
  override_supports_parallel_calls? : (&EmbeddingModelV4) -> Bool,
  wrap_embed? : async (EmbeddingModelV4MiddlewareContext) -> EmbeddingModelV4Result,
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
/// Apply the optional embedding parameter transform.
pub async fn EmbeddingModelV4Middleware::transform(
  self : EmbeddingModelV4Middleware,
  model : &EmbeddingModelV4,
  params : EmbeddingModelV4CallOptions,
) -> EmbeddingModelV4CallOptions {
  match self.transform_params {
    Some(transform) => transform(params, model)
    None => params
  }
}
