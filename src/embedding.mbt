///|
/// Options shared by provider-neutral embedding calls.
pub(all) struct EmbeddingOptions {
  dimensions : Int?
  user : String?
  headers : Map[String, String]
  provider_options : Map[String, Json]
} derive(Debug)

///|
/// Construct normalized embedding options.
pub fn EmbeddingOptions::new(
  dimensions? : Int,
  user? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
) -> EmbeddingOptions {
  { dimensions, user, headers, provider_options }
}

///|
/// Result returned by the model layer for one or more values.
pub(all) struct EmbeddingBatchResponse {
  embeddings : Array[Array[Double]]
  usage : Usage
} derive(Debug, Eq)

///|
/// Result returned by the single-value `embed` helper.
pub(all) struct EmbeddingResponse {
  embedding : Array[Double]
  usage : Usage
} derive(Debug, Eq)

///|
/// Embed one text value.
pub async fn embed(
  model : &EmbeddingModel,
  value : String,
  dimensions? : Int,
  user? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
) -> EmbeddingResponse {
  let response = model.embed(
    [value],
    EmbeddingOptions::new(dimensions?, user?, headers~, provider_options~),
  )
  guard response.embeddings.length() == 1 else {
    fail(
      "embedding provider returned \{response.embeddings.length()} embeddings for 1 value",
    )
  }
  { embedding: response.embeddings[0], usage: response.usage }
}

///|
/// Embed multiple text values, splitting calls at the model's batch limit.
pub async fn embed_many(
  model : &EmbeddingModel,
  values : Array[String],
  dimensions? : Int,
  user? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
) -> EmbeddingBatchResponse {
  guard values.length() > 0 else {
    fail("embed_many requires at least one value")
  }
  let max_embeddings_per_call = model.max_embeddings_per_call()
  guard max_embeddings_per_call > 0 else {
    fail("embedding model max_embeddings_per_call must be greater than zero")
  }
  let embeddings : Array[Array[Double]] = []
  let mut usage = Usage::zero()
  let mut offset = 0
  while offset < values.length() {
    let remaining = values.length() - offset
    let batch_size = if remaining < max_embeddings_per_call {
      remaining
    } else {
      max_embeddings_per_call
    }
    let batch : Array[String] = []
    for index in offset..<(offset + batch_size) {
      batch.push(values[index])
    }
    let response = model.embed(
      batch,
      EmbeddingOptions::new(dimensions?, user?, headers~, provider_options~),
    )
    guard response.embeddings.length() == batch_size else {
      fail(
        "embedding provider returned \{response.embeddings.length()} embeddings for \{batch_size} values",
      )
    }
    for embedding in response.embeddings {
      embeddings.push(embedding)
    }
    usage = usage.add(response.usage)
    offset = offset + batch_size
  }
  { embeddings, usage }
}

///|
/// Camel-case compatibility alias for AI SDK's `embedMany`.
pub async fn embedMany(
  model : &EmbeddingModel,
  values : Array[String],
  dimensions? : Int,
  user? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
) -> EmbeddingBatchResponse {
  embed_many(model, values, dimensions?, user?, headers~, provider_options~)
}
