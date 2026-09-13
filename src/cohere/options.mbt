///|
/// Cohere chat model ids (https://docs.cohere.com/docs/models).
pub type CohereChatModelId = String

///|
/// Cohere embedding model ids, e.g. `embed-v4.0`.
pub type CohereEmbeddingModelId = String

///|
/// Cohere reranking model ids, e.g. `rerank-v3.5`.
pub type CohereRerankingModelId = String

///|
/// Provider options accepted under the `cohere` namespace:
///
/// - chat: `thinking` (`{ type: "enabled" | "disabled", tokenBudget? }`).
/// - image parts: `detail` (`"auto" | "low" | "high"`).
/// - embedding: `inputType` (`"search_query" | "search_document" | ...`),
///   `truncate` (`"NONE" | "START" | "END"`), `outputDimension` (int).
/// - reranking: `maxTokensPerDoc` (int), `priority` (bool).
