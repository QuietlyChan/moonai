///|
/// The language-model operation currently being transformed by middleware.
pub(all) enum LanguageModelV4MiddlewareOperation {
  Generate
  Stream
} derive(Debug, Eq)

///|
/// Parameters and model identity visible to a V4 middleware transform.
pub(all) struct LanguageModelV4TransformContext {
  operation : LanguageModelV4MiddlewareOperation
  params : LanguageModelV4CallOptions
  model : &LanguageModelV4
}

///|
/// Context passed to V4 language-model operation wrappers.
pub(all) struct LanguageModelV4MiddlewareContext {
  params : LanguageModelV4CallOptions
  model : &LanguageModelV4
  do_generate : async () -> LanguageModelV4GenerateResult
  do_stream : async () -> LanguageModelV4StreamResult
}

///|
/// Delegate to the wrapped model's generate operation.
pub async fn LanguageModelV4MiddlewareContext::generate(
  self : LanguageModelV4MiddlewareContext,
) -> LanguageModelV4GenerateResult {
  (self.do_generate)()
}

///|
/// Delegate to the wrapped model's stream operation.
pub async fn LanguageModelV4MiddlewareContext::stream(
  self : LanguageModelV4MiddlewareContext,
) -> LanguageModelV4StreamResult {
  (self.do_stream)()
}

///|
/// Provider-level middleware contract for `LanguageModelV4`.
///
/// Wrapping and middleware composition belong to the high-level `ai/model`
/// package. Keeping this contract in `provider` lets providers and middleware
/// libraries share it without depending on the workflow layer.
pub(all) struct LanguageModelV4Middleware {
  transform_params : (async (LanguageModelV4TransformContext) -> LanguageModelV4CallOptions)?
  override_provider : ((&LanguageModelV4) -> String)?
  override_model_id : ((&LanguageModelV4) -> String)?
  override_supported_urls : ((&LanguageModelV4) -> Array[SupportedUrlRule])?
  wrap_generate : (async (LanguageModelV4MiddlewareContext) -> LanguageModelV4GenerateResult)?
  wrap_stream : (async (LanguageModelV4MiddlewareContext) -> LanguageModelV4StreamResult)?
}

///|
/// Construct a V4 language-model middleware contract.
pub fn LanguageModelV4Middleware::new(
  transform_params? : async (LanguageModelV4TransformContext) -> LanguageModelV4CallOptions,
  override_provider? : (&LanguageModelV4) -> String,
  override_model_id? : (&LanguageModelV4) -> String,
  override_supported_urls? : (&LanguageModelV4) -> Array[SupportedUrlRule],
  wrap_generate? : async (LanguageModelV4MiddlewareContext) -> LanguageModelV4GenerateResult,
  wrap_stream? : async (LanguageModelV4MiddlewareContext) -> LanguageModelV4StreamResult,
) -> LanguageModelV4Middleware {
  {
    transform_params,
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
/// Apply the optional parameter transform.
pub async fn LanguageModelV4Middleware::transform(
  self : LanguageModelV4Middleware,
  operation : LanguageModelV4MiddlewareOperation,
  model : &LanguageModelV4,
  params : LanguageModelV4CallOptions,
) -> LanguageModelV4CallOptions {
  match self.transform_params {
    Some(transform) => transform({ operation, params, model })
    None => params
  }
}
