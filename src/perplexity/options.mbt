///|
/// Perplexity language model ids, e.g. `sonar`, `sonar-pro`,
/// `sonar-reasoning-pro` (https://docs.perplexity.ai/models/model-cards).
pub type PerplexityLanguageModelId = String

///|
/// Perplexity embedding model ids, e.g. `pplx-embed-v1`.
pub type PerplexityEmbeddingModelId = String

///|
/// Provider options accepted under the `perplexity` namespace (all optional,
/// wire names as given): `search_domain_filter`, `return_images`,
/// `return_related_questions`, `search_after_date_filter`,
/// `search_before_date_filter`, `last_updated_after_filter`,
/// `last_updated_before_filter`, `search_recency_filter`, `web_search_options`
/// (`search_context_size`), `disable_search`, `enable_search_classifier`.
