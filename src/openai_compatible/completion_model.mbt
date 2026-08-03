///|
/// A model using the legacy OpenAI `/completions` wire protocol.
pub struct OpenAICompatibleCompletionModel {
  priv provider_name : String
  priv api_key : String
  priv base_url : String
  priv model_id : String
  priv headers : Map[String, String]
  priv include_usage : Bool
  priv idle_timeout_ms : Int
}

///|
/// Construct an OpenAI-compatible completion model directly.
pub fn openai_compatible_completion(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  include_usage? : Bool = true,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompatibleCompletionModel {
  {
    provider_name: "\{provider_name}.completion",
    api_key,
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
    headers: @provider_utils.copy_headers(headers),
    include_usage,
    idle_timeout_ms,
  }
}

///|
fn OpenAICompatibleCompletionModel::completions_url(
  self : OpenAICompatibleCompletionModel,
) -> String {
  @provider_utils.append_path(self.base_url, "/completions")
}

///|
fn OpenAICompatibleCompletionModel::request_headers(
  self : OpenAICompatibleCompletionModel,
) -> Map[String, String] {
  let headers = @provider_utils.copy_headers(self.headers)
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  if self.api_key != "" {
    headers["Authorization"] = "Bearer \{self.api_key}"
  }
  headers
}

///|
pub impl @moonai.CompletionModel for OpenAICompatibleCompletionModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @moonai.CompletionModel for OpenAICompatibleCompletionModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @moonai.CompletionModel for OpenAICompatibleCompletionModel with fn generate(
  self,
  options,
) {
  self.generate_completion(options)
}

///|
pub impl @moonai.CompletionModel for OpenAICompatibleCompletionModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_completion(options, on_event)
}

///|
async fn OpenAICompatibleCompletionModel::generate_completion(
  self : OpenAICompatibleCompletionModel,
  options : @moonai.CompletionOptions,
) -> @moonai.CompletionResponse {
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.completions_url(),
    headers=@provider_utils.merge_headers(
      self.request_headers(),
      options.headers,
    ),
    body=encode_completion_request(self.model_id, options, stream=false),
    timeout_ms=self.idle_timeout_ms,
  )
  decode_completion_response(response)
}

///|
async fn OpenAICompatibleCompletionModel::stream_completion(
  self : OpenAICompatibleCompletionModel,
  options : @moonai.CompletionOptions,
  on_event : async (@moonai.StreamEvent) -> Unit,
) -> @moonai.CompletionResponse {
  let decoder = OpenAICompatibleCompletionStreamDecoder::new(
    include_raw_chunks=options.include_raw_chunks,
  )
  @http_sse.post_json_sse(
    provider_name=self.provider_name,
    url=self.completions_url(),
    headers=@provider_utils.merge_headers(
      self.request_headers(),
      options.headers,
    ),
    body=encode_completion_request(
      self.model_id,
      options,
      include_usage=self.include_usage,
    ),
    idle_timeout_ms=self.idle_timeout_ms,
    expected_terminator="[DONE]",
    feed_line=raw => decoder.feed_line(raw),
    flush_buffered=() => decoder.flush_buffered(),
    response=() => decoder.response(),
    on_event~,
  )
}
