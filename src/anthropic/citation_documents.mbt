///|
/// Document metadata used to resolve Anthropic page and character citations.
/// Anthropic citations only carry a document index, so the response mapper
/// keeps the same ordered registry as the AI SDK implementation.
priv struct AnthropicCitationDocument {
  title : String
  filename : String?
  media_type : String
}

///|
/// Collect citation-enabled PDF and plain-text files from user messages.
fn extract_anthropic_citation_documents(
  prompt : @provider.LanguageModelV4Prompt,
  provider_name : String,
) -> Array[AnthropicCitationDocument] {
  let documents : Array[AnthropicCitationDocument] = []
  for message in prompt.messages {
    match message {
      @provider.V4UserMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptFile(
              media_type~,
              filename~,
              provider_options~,
              ..
            ) if (media_type == "application/pdf" || media_type == "text/plain") &&
              anthropic_document_citations(
                resolve_anthropic_prompt_options(
                  provider_options, provider_name,
                ),
              )
              is Some(_) =>
              documents.push({
                title: filename.unwrap_or("Untitled Document"),
                filename,
                media_type,
              })
            _ => ()
          }
        }
      _ => ()
    }
  }
  documents
}

///|
/// A successful web-fetch result becomes addressable by later citation
/// deltas in the same response stream.
fn anthropic_web_fetch_citation_document(
  block : Json,
) -> AnthropicCitationDocument? {
  guard block
    is { "type": "web_fetch_tool_result", "content": Object(result), .. } &&
    result.get("type") is Some(String("web_fetch_result")) else {
    return None
  }
  guard result.get("url") is Some(String(url)) &&
    result.get("content") is Some(Object(document)) &&
    document.get("source") is Some(Object(source)) &&
    source.get("media_type") is Some(String(media_type)) else {
    return None
  }
  let title = match document.get("title") {
    Some(String(value)) => value
    _ => url
  }
  Some({ title, filename: None, media_type })
}
