///|
type ApiKey = String

///|
/// Configuration shared by models created from one OpenAI-compatible endpoint.
pub struct OpenAIProvider {
  priv provider_name : String
  priv api_key : ApiKey
  priv base_url : String
  priv headers : Map[String, String]
  priv preserve_reasoning : Bool
  priv idle_timeout_ms : Int
}

///|
fn copy_headers(headers : Map[String, String]) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in headers.iter2() {
    let (key, value) = entry
    result[key] = value
  }
  result
}

///|
/// Create a reusable OpenAI-compatible provider factory.
pub fn create_openai(
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  provider_name? : String = "openai",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAIProvider {
  {
    provider_name,
    api_key,
    base_url,
    headers: copy_headers(headers),
    preserve_reasoning,
    idle_timeout_ms,
  }
}

///|
/// Select a model from this provider.
pub fn OpenAIProvider::chat(
  self : OpenAIProvider,
  model_id : String,
) -> OpenAICompatibleModel {
  {
    provider_name: self.provider_name,
    api_key: self.api_key,
    base_url: self.base_url,
    model_id,
    headers: copy_headers(self.headers),
    preserve_reasoning: self.preserve_reasoning,
    idle_timeout_ms: self.idle_timeout_ms,
  }
}

///|
/// One chat model served through the OpenAI Chat Completions protocol.
pub struct OpenAICompatibleModel {
  priv provider_name : String
  priv api_key : ApiKey
  priv base_url : String
  priv model_id : String
  priv headers : Map[String, String]
  priv preserve_reasoning : Bool
  priv idle_timeout_ms : Int
}

///|
/// Construct an official OpenAI model directly.
pub fn openai(
  model_id : String,
  api_key~ : String,
  base_url? : String = "https://api.openai.com/v1",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompatibleModel {
  create_openai(api_key~, base_url~, headers~, idle_timeout_ms~).chat(model_id)
}

///|
/// Construct a model for DeepSeek, OpenRouter, Ollama, vLLM, or another
/// OpenAI-compatible endpoint.
pub fn openai_compatible(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  preserve_reasoning? : Bool = false,
  idle_timeout_ms? : Int = 120_000,
) -> OpenAICompatibleModel {
  create_openai(
    api_key~,
    base_url~,
    provider_name~,
    headers~,
    preserve_reasoning~,
    idle_timeout_ms~,
  ).chat(model_id)
}

///|
fn OpenAICompatibleModel::chat_completions_url(
  self : OpenAICompatibleModel,
) -> String {
  if self.base_url.strip_suffix("/chat/completions") is Some(_) {
    self.base_url
  } else {
    let base = self.base_url.strip_suffix("/").unwrap_or(self.base_url)
    "\{base}/chat/completions"
  }
}

///|
fn OpenAICompatibleModel::request_headers(
  self : OpenAICompatibleModel,
) -> Map[String, String] {
  let headers = copy_headers(self.headers)
  headers["Content-Type"] = "application/json"
  headers["Accept-Encoding"] = "identity"
  if self.api_key != "" {
    headers["Authorization"] = "Bearer \{self.api_key}"
  }
  headers
}

///|
pub impl @moonai.ChatModel for OpenAICompatibleModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @moonai.ChatModel for OpenAICompatibleModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @moonai.ChatModel for OpenAICompatibleModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_chat(options, on_event)
}
