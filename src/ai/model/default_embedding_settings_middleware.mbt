///|
/// Default embedding-settings middleware.
///
/// Applies default headers and provider options to an embedding model,
/// mirroring the language-model `default_settings_middleware`: values
/// already present on the call win, unset fields fall back to the
/// configured defaults.
pub fn default_embedding_settings_middleware(
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
) -> @provider.EmbeddingModelV4Middleware {
  @provider.EmbeddingModelV4Middleware::new(transform_params=fn(
    params,
    _model,
  ) {
    {
      ..params,
      headers: @provider_utils.merge_headers(headers, params.headers),
      provider_options: @provider.merge_provider_metadata(
        provider_options,
        params.provider_options,
      ),
    }
  })
}
