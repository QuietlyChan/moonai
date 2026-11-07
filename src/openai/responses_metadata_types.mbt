///|
/// Response-level metadata produced by the OpenAI Responses API.
#derive(Debug, Eq)
pub(all) struct OpenAIResponsesMetadata {
  response_id : String?
  logprobs : Array[Json]?
  service_tier : String?
  reasoning_context : String?
}

///|
/// Construct response-level OpenAI metadata.
pub fn OpenAIResponsesMetadata::new(
  response_id? : String,
  logprobs? : Array[Json],
  service_tier? : String,
  reasoning_context? : String,
) -> OpenAIResponsesMetadata {
  { response_id, logprobs, service_tier, reasoning_context, }
}

///|
fn OpenAIResponsesMetadata::to_json(self : OpenAIResponsesMetadata) -> Json {
  let fields : Map[String, Json] = Map([])
  match self.response_id {
    Some(value) => fields["responseId"] = Json::string(value)
    None => fields["responseId"] = Json::null()
  }
  if self.logprobs is Some(value) {
    fields["logprobs"] = Json::array(value)
  }
  if self.service_tier is Some(value) {
    fields["serviceTier"] = Json::string(value)
  }
  if self.reasoning_context is Some(value) {
    fields["reasoningContext"] = Json::string(value)
  }
  Json::object(fields)
}

///|
/// Provider-keyed response metadata using the AI SDK public type name.
#derive(Debug, Eq)
pub(all) struct OpenaiResponsesProviderMetadata {
  openai : OpenAIResponsesMetadata
}

///|
/// Construct provider-keyed response metadata.
pub fn OpenaiResponsesProviderMetadata::new(
  openai~ : OpenAIResponsesMetadata,
) -> OpenaiResponsesProviderMetadata {
  { openai, }
}

///|
/// Convert typed response metadata to the provider-neutral metadata map.
pub fn OpenaiResponsesProviderMetadata::to_provider_metadata(
  self : OpenaiResponsesProviderMetadata,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  Map([(provider_name, self.openai.to_json())])
}

///|
/// Reasoning-part metadata produced by OpenAI Responses.
#derive(Debug, Eq)
pub(all) struct OpenAIResponsesReasoningMetadata {
  item_id : String
  reasoning_encrypted_content : String?
}

///|
/// Provider-keyed reasoning metadata using the AI SDK public type name.
#derive(Debug, Eq)
pub(all) struct OpenaiResponsesReasoningProviderMetadata {
  openai : OpenAIResponsesReasoningMetadata
}

///|
/// Construct provider-keyed reasoning metadata.
pub fn OpenaiResponsesReasoningProviderMetadata::new(
  item_id~ : String,
  reasoning_encrypted_content? : String,
) -> OpenaiResponsesReasoningProviderMetadata {
  { openai: { item_id, reasoning_encrypted_content, }, }
}

///|
/// Convert reasoning metadata to the provider-neutral metadata map.
pub fn OpenaiResponsesReasoningProviderMetadata::to_provider_metadata(
  self : OpenaiResponsesReasoningProviderMetadata,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([
    ("itemId", Json::string(self.openai.item_id)),
  ])
  if self.openai.reasoning_encrypted_content is Some(value) {
    fields["reasoningEncryptedContent"] = Json::string(value)
  }
  Map([(provider_name, Json::object(fields))])
}

///|
/// Compaction-part metadata produced by OpenAI Responses.
#derive(Debug, Eq)
pub(all) struct OpenAIResponsesCompactionMetadata {
  item_id : String
  encrypted_content : String?
}

///|
/// Provider-keyed compaction metadata using the AI SDK public type name.
#derive(Debug, Eq)
pub(all) struct OpenaiResponsesCompactionProviderMetadata {
  openai : OpenAIResponsesCompactionMetadata
}

///|
/// Construct provider-keyed compaction metadata.
pub fn OpenaiResponsesCompactionProviderMetadata::new(
  item_id~ : String,
  encrypted_content? : String,
) -> OpenaiResponsesCompactionProviderMetadata {
  { openai: { item_id, encrypted_content, }, }
}

///|
/// Convert compaction metadata to the provider-neutral metadata map.
pub fn OpenaiResponsesCompactionProviderMetadata::to_provider_metadata(
  self : OpenaiResponsesCompactionProviderMetadata,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([
    ("type", Json::string("compaction")),
    ("itemId", Json::string(self.openai.item_id)),
  ])
  if self.openai.encrypted_content is Some(value) {
    fields["encryptedContent"] = Json::string(value)
  }
  Map([(provider_name, Json::object(fields))])
}

///|
/// Phase attached to one OpenAI Responses output-text item.
#derive(Debug, Eq)
pub(all) enum OpenAIResponsesTextPhase {
  ResponsesTextCommentary
  ResponsesTextFinalAnswer
}

///|
fn OpenAIResponsesTextPhase::wire_name(
  self : OpenAIResponsesTextPhase,
) -> String {
  match self {
    ResponsesTextCommentary => "commentary"
    ResponsesTextFinalAnswer => "final_answer"
  }
}

///|
/// Text-part metadata produced by OpenAI Responses.
#derive(Debug, Eq)
pub(all) struct OpenAIResponsesTextMetadata {
  item_id : String
  phase : OpenAIResponsesTextPhase?
  annotations : Array[Json]?
}

///|
/// Provider-keyed text metadata using the AI SDK public type name.
#derive(Debug, Eq)
pub(all) struct OpenaiResponsesTextProviderMetadata {
  openai : OpenAIResponsesTextMetadata
}

///|
/// Construct provider-keyed output-text metadata.
pub fn OpenaiResponsesTextProviderMetadata::new(
  item_id~ : String,
  phase? : OpenAIResponsesTextPhase,
  annotations? : Array[Json],
) -> OpenaiResponsesTextProviderMetadata {
  { openai: { item_id, phase, annotations, }, }
}

///|
/// Convert output-text metadata to the provider-neutral metadata map.
pub fn OpenaiResponsesTextProviderMetadata::to_provider_metadata(
  self : OpenaiResponsesTextProviderMetadata,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([
    ("itemId", Json::string(self.openai.item_id)),
  ])
  if self.openai.phase is Some(value) {
    fields["phase"] = Json::string(value.wire_name())
  }
  if self.openai.annotations is Some(value) {
    fields["annotations"] = Json::array(value)
  }
  Map([(provider_name, Json::object(fields))])
}

///|
/// Source-document metadata emitted by OpenAI Responses annotations.
#derive(Debug, Eq)
pub(all) enum OpenAIResponsesSourceDocumentMetadata {
  ResponsesFileCitation(file_id~ : String, index~ : Int32)
  ResponsesContainerFileCitation(file_id~ : String, container_id~ : String)
  ResponsesFilePath(file_id~ : String, index~ : Int32)
}

///|
fn OpenAIResponsesSourceDocumentMetadata::to_json(
  self : OpenAIResponsesSourceDocumentMetadata,
) -> Json {
  match self {
    ResponsesFileCitation(file_id~, index~) =>
      { "type": "file_citation", "fileId": file_id, "index": index }
    ResponsesContainerFileCitation(file_id~, container_id~) =>
      {
        "type": "container_file_citation",
        "fileId": file_id,
        "containerId": container_id,
      }
    ResponsesFilePath(file_id~, index~) =>
      { "type": "file_path", "fileId": file_id, "index": index }
  }
}

///|
/// Provider-keyed source-document metadata using the AI SDK public type name.
#derive(Debug, Eq)
pub(all) struct OpenaiResponsesSourceDocumentProviderMetadata {
  openai : OpenAIResponsesSourceDocumentMetadata
}

///|
/// Construct provider-keyed source-document metadata.
pub fn OpenaiResponsesSourceDocumentProviderMetadata::new(
  openai~ : OpenAIResponsesSourceDocumentMetadata,
) -> OpenaiResponsesSourceDocumentProviderMetadata {
  { openai, }
}

///|
/// Convert source-document metadata to the provider-neutral metadata map.
pub fn OpenaiResponsesSourceDocumentProviderMetadata::to_provider_metadata(
  self : OpenaiResponsesSourceDocumentProviderMetadata,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  Map([(provider_name, self.openai.to_json())])
}
