///|
/// Baseten chat model ids. Dedicated deployments are addressed through the
/// provider's `model_url` instead of a model id.
pub type BasetenChatModelId = String

///|
/// Baseten embedding model ids for dedicated BEI deployments.
pub type BasetenEmbeddingModelId = String

///|
/// Baseten's per-request embedding input limit: larger batches are rejected
/// with `413 batch size N > maximum allowed batch size 128`. `embed_many`
/// splits larger inputs into chunks of this size.
pub const MAX_EMBEDDINGS_PER_CALL : Int = 128
