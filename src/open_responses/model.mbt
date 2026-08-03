///|
/// Configuration for one Open Responses compatible endpoint.
pub struct OpenResponsesProvider {
  priv provider_name : String
  priv url : String
  priv api_key : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
}

///|
/// Create an Open Responses provider from an exact Responses API endpoint URL.
pub fn create_open_responses(
  provider_name~ : String,
  url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
) -> OpenResponsesProvider {
  {
    provider_name,
    url: @provider_utils.without_trailing_slash(url),
    api_key,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
  }
}

///|
/// AI SDK-style camel-case provider factory.
pub fn createOpenResponses(
  name~ : String,
  url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
) -> OpenResponsesProvider {
  create_open_responses(
    provider_name=name,
    url~,
    api_key~,
    headers~,
    idle_timeout_ms~,
  )
}

///|
/// Select an Open Responses language model.
pub fn OpenResponsesProvider::language_model(
  self : OpenResponsesProvider,
  model_id : String,
) -> OpenResponsesLanguageModel {
  {
    provider_name: "\{self.provider_name}.responses",
    url: self.url,
    api_key: self.api_key,
    model_id,
    headers: @provider_utils.copy_headers(self.headers),
    idle_timeout_ms: self.idle_timeout_ms,
  }
}

///|
/// Camel-case compatibility alias for `language_model`.
pub fn OpenResponsesProvider::languageModel(
  self : OpenResponsesProvider,
  model_id : String,
) -> OpenResponsesLanguageModel {
  self.language_model(model_id)
}

///|
/// Select a model using the Responses API name.
pub fn OpenResponsesProvider::responses(
  self : OpenResponsesProvider,
  model_id : String,
) -> OpenResponsesLanguageModel {
  self.language_model(model_id)
}

///|
/// Short alias for `language_model`.
pub fn OpenResponsesProvider::model(
  self : OpenResponsesProvider,
  model_id : String,
) -> OpenResponsesLanguageModel {
  self.language_model(model_id)
}

///|
/// A model served through the Open Responses protocol.
pub struct OpenResponsesLanguageModel {
  priv provider_name : String
  priv url : String
  priv api_key : String
  priv model_id : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
}

///|
/// Return warnings for standardized settings that the Responses protocol
/// cannot represent faithfully.
fn open_responses_warnings(
  options : @moonai.ChatCallOptions,
) -> Array[@moonai.Warning] {
  let warnings : Array[@moonai.Warning] = []
  if options.stop_sequences.length() > 0 {
    warnings.push(
      @moonai.Warning::Unsupported(
        feature="stopSequences",
        details="Open Responses has no portable stop-sequences field.",
      ),
    )
  }
  if options.seed is Some(_) {
    warnings.push(
      @moonai.Warning::Unsupported(
        feature="seed",
        details="The Responses protocol does not define a seed setting.",
      ),
    )
  }
  if options.frequency_penalty is Some(_) {
    warnings.push(
      @moonai.Warning::Unsupported(
        feature="frequencyPenalty",
        details="The Responses protocol does not define frequency penalty.",
      ),
    )
  }
  if options.presence_penalty is Some(_) {
    warnings.push(
      @moonai.Warning::Unsupported(
        feature="presencePenalty",
        details="The Responses protocol does not define presence penalty.",
      ),
    )
  }
  warnings
}

///|
/// Construct an Open Responses model directly.
pub fn open_responses(
  model_id~ : String,
  provider_name~ : String,
  url~ : String,
  api_key? : String = "",
  headers? : Map[String, String] = Map([]),
  idle_timeout_ms? : Int = 120_000,
) -> OpenResponsesLanguageModel {
  create_open_responses(
    provider_name~,
    url~,
    api_key~,
    headers~,
    idle_timeout_ms~,
  ).language_model(model_id)
}

///|
fn OpenResponsesLanguageModel::request_headers(
  self : OpenResponsesLanguageModel,
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
pub impl @moonai.ChatModel for OpenResponsesLanguageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @moonai.ChatModel for OpenResponsesLanguageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @moonai.ChatModel for OpenResponsesLanguageModel with fn generate(
  self,
  options,
) {
  self.generate_responses(options)
}

///|
pub impl @moonai.ChatModel for OpenResponsesLanguageModel with fn stream(
  self,
  options,
  on_event,
) {
  self.stream_responses(options, on_event)
}
