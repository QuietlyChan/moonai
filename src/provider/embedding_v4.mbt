///|
/// Call options for the AI SDK-aligned embedding model contract.
///
/// Retry policy is a MoonBit runtime extension: JavaScript providers receive
/// retry behavior from the high-level package, while MoonBit transports keep
/// it on the call so adapters can remain cancellation-aware.
#derive(Debug)
pub(all) struct EmbeddingModelV4CallOptions {
  values : Array[String]
  headers : Map[String, String]
  provider_options : Map[String, Json]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
}

///|
/// Construct V4 embedding call options.
pub fn EmbeddingModelV4CallOptions::new(
  values : Array[String],
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> EmbeddingModelV4CallOptions {
  {
    values: values.copy(),
    headers,
    provider_options,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Token usage returned by an embedding model.
///
/// Providers that do not report usage return `None` from the model result.
#derive(Debug, Eq)
pub(all) struct EmbeddingModelV4Usage {
  tokens : Int32?
}

///|
/// Construct known embedding usage.
pub fn EmbeddingModelV4Usage::new(tokens : Int32) -> EmbeddingModelV4Usage {
  { tokens: Some(tokens), }
}

///|
/// Result of one V4 embedding model call.
#derive(Debug, Eq)
pub(all) struct EmbeddingModelV4Result {
  embeddings : Array[Array[Double]]
  usage : EmbeddingModelV4Usage?
  provider_metadata : Map[String, Json]
  request : RequestMetadata?
  response : ResponseMetadata?
  warnings : Array[Warning]
}

///|
/// Construct a V4 result.
pub fn EmbeddingModelV4Result::new(
  embeddings : Array[Array[Double]],
  usage? : EmbeddingModelV4Usage,
  provider_metadata? : Map[String, Json] = Map([]),
  request? : RequestMetadata,
  response? : ResponseMetadata,
  warnings? : Array[Warning] = [],
) -> EmbeddingModelV4Result {
  {
    embeddings,
    usage,
    provider_metadata: copy_provider_metadata(provider_metadata),
    request,
    response,
    warnings: copy_warnings(warnings),
  }
}

///|
/// Convert an existing provider response at an explicit wire boundary.
pub fn EmbeddingModelV4Result::from_batch_response(
  response : EmbeddingBatchResponse,
) -> EmbeddingModelV4Result {
  EmbeddingModelV4Result::new(
    response.embeddings.copy(),
    usage=EmbeddingModelV4Usage::new(response.usage.input_tokens),
    provider_metadata=response.provider_metadata,
    request?=response.request,
    response?=response.response,
    warnings=response.warnings,
  )
}

///|
/// Convert a V4 result to the high-level aggregation shape used by `ai`.
pub fn EmbeddingModelV4Result::to_batch_response(
  self : EmbeddingModelV4Result,
) -> EmbeddingBatchResponse {
  let usage = match self.usage {
    Some(value) =>
      Usage::new(input_tokens=value.tokens.unwrap_or(0), output_tokens=0)
    None => Usage::zero()
  }
  EmbeddingBatchResponse::new(self.embeddings, usage).with_diagnostics(
    self.request,
    self.response,
    self.provider_metadata,
    self.warnings,
  )
}

///|
/// Versioned provider contract for text embeddings.
pub(open) trait EmbeddingModelV4 {
  fn specification_version(Self) -> String
  fn provider(Self) -> String
  fn model_id(Self) -> String
  fn max_embeddings_per_call(Self) -> Int32?
  /// Experimental UTF-8 input-byte budget for one embedding call, mirroring
  /// AI SDK's `maxInputBytesPerCall` capability. `None` means no byte limit.
  fn max_input_bytes_per_call(Self) -> Int64?
  fn supports_parallel_calls(Self) -> Bool
  async fn do_embed(Self, EmbeddingModelV4CallOptions) -> EmbeddingModelV4Result
}

///|
pub extend EmbeddingModelV4CallOptions with Debug::{to_repr}

///|
pub extend EmbeddingModelV4Usage with Debug::{to_repr}

///|
pub extend EmbeddingModelV4Usage with Eq::{not_equal, equal}

///|
pub extend EmbeddingModelV4Result with Debug::{to_repr}

///|
pub extend EmbeddingModelV4Result with Eq::{not_equal, equal}
