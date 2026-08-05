///|
test "OpenAI Responses metadata bridges typed and provider-neutral forms" {
  let typed = OpenaiResponsesProviderMetadata::new(
    openai=OpenAIResponsesMetadata::new(
      response_id="resp-1",
      logprobs=[[{ "token": "Moon" }]],
      service_tier="priority",
      reasoning_context="ctx-1",
    ),
  )
  let metadata = typed.to_provider_metadata()
  json_inspect(metadata, content={
    "openai": {
      "responseId": "resp-1",
      "logprobs": [[{ "token": "Moon" }]],
      "serviceTier": "priority",
      "reasoningContext": "ctx-1",
    },
  })
  assert_eq(decode_openai_responses_provider_metadata(metadata), Some(typed))
}

///|
test "OpenAI content metadata uses AI SDK wire field names" {
  json_inspect(
    OpenaiResponsesReasoningProviderMetadata::new(
      item_id="reason-1",
      reasoning_encrypted_content="encrypted",
    ).to_provider_metadata(),
    content={
      "openai": {
        "itemId": "reason-1",
        "reasoningEncryptedContent": "encrypted",
      },
    },
  )
  json_inspect(
    OpenaiResponsesCompactionProviderMetadata::new(
      item_id="compact-1",
      encrypted_content="ciphertext",
    ).to_provider_metadata(),
    content={
      "openai": {
        "type": "compaction",
        "itemId": "compact-1",
        "encryptedContent": "ciphertext",
      },
    },
  )
  json_inspect(
    OpenaiResponsesTextProviderMetadata::new(
      item_id="message-1",
      phase=ResponsesTextFinalAnswer,
      annotations=[{ "type": "url_citation" }],
    ).to_provider_metadata(),
    content={
      "openai": {
        "itemId": "message-1",
        "phase": "final_answer",
        "annotations": [{ "type": "url_citation" }],
      },
    },
  )
  json_inspect(
    OpenaiResponsesSourceDocumentProviderMetadata::new(
      openai=ResponsesContainerFileCitation(
        file_id="file-1",
        container_id="container-1",
      ),
    ).to_provider_metadata(),
    content={
      "openai": {
        "type": "container_file_citation",
        "fileId": "file-1",
        "containerId": "container-1",
      },
    },
  )
}
