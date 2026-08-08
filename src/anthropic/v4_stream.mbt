///|
fn anthropic_stream_index(json : Json?) -> Int? {
  match json {
    Some({ "index": Number(index, ..), .. }) => Some(index.to_int())
    _ => None
  }
}

///|
/// AI SDK V4 transform over the Anthropic Messages wire decoder.
priv struct AnthropicV4StreamDecoder {
  decoder : AnthropicStreamDecoder
  emit_raw_chunks : Bool
  mut raw_event : Json?
}

///|
fn AnthropicV4StreamDecoder::new(
  emit_raw_chunks~ : Bool,
  provider_name~ : String,
  canonical_metadata~ : Bool,
  include_custom_provider_metadata~ : Bool,
  mark_code_execution_dynamic~ : Bool,
  uses_json_response_tool~ : Bool,
  tool_name_mapping~ : @provider_utils.ToolNameMapping,
  id_generator~ : @provider_utils.IdGenerator,
  citation_documents~ : Array[AnthropicCitationDocument],
) -> AnthropicV4StreamDecoder {
  {
    decoder: AnthropicStreamDecoder::new_with_metadata_policy(
      // Provider-native frames carry citations, signatures, and server-tool
      // state used by the V4 transform even when raw output is disabled.
      include_raw_chunks=true,
      provider_name~,
      canonical_metadata~,
      include_custom_provider_metadata~,
      mark_code_execution_dynamic~,
      uses_json_response_tool~,
      tool_name_mapping~,
      id_generator~,
      citation_documents~,
    ),
    emit_raw_chunks,
    raw_event: None,
  }
}

///|
fn AnthropicV4StreamDecoder::v4_batch(
  self : AnthropicV4StreamDecoder,
  batch : @provider_utils.SseDecodeBatch[@provider.StreamEvent],
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  for event in batch.events {
    match event {
      @provider.StreamStart | @provider.Warning(_) => ()
      @provider.Raw(value) => {
        self.raw_event = Some(value)
        if self.emit_raw_chunks {
          events.push(@provider.V4Raw(value))
        }
        match self.decoder.v4_side_event(value) {
          Some(part) => events.push(part)
          None => ()
        }
      }
      @provider.Finish(..) =>
        events.push(
          @provider.V4Finish(
            usage=self.decoder.v4_usage(),
            reason=self.decoder.v4_finish_reason(),
            provider_metadata=self.decoder.provider_metadata_snapshot(),
          ),
        )
      other =>
        match self.decoder.v4_stream_part(other, self.raw_event) {
          Some(part) => events.push(part)
          None => ()
        }
    }
  }
  { events, consumed_event: batch.consumed_event, done: batch.done }
}

///|
fn AnthropicV4StreamDecoder::feed_line(
  self : AnthropicV4StreamDecoder,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  self.v4_batch(self.decoder.feed_line(raw))
}

///|
fn AnthropicV4StreamDecoder::flush_buffered(
  self : AnthropicV4StreamDecoder,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  self.v4_batch(self.decoder.flush_buffered())
}

///|
fn AnthropicV4StreamDecoder::response_metadata_snapshot(
  self : AnthropicV4StreamDecoder,
) -> @provider.ResponseMetadata? {
  self.decoder.response_metadata_snapshot()
}

///|
fn AnthropicStreamDecoder::v4_text_start_metadata(
  self : AnthropicStreamDecoder,
  raw : Json?,
) -> Map[String, Json] {
  match anthropic_stream_index(raw) {
    Some(index) if index >= 0 &&
      index < self.block_kinds.length() &&
      self.block_kinds[index] == "compaction" =>
      self.metadata_map({ "type": "compaction" })
    _ => Map([])
  }
}

///|
fn AnthropicStreamDecoder::v4_reasoning_start_metadata(
  self : AnthropicStreamDecoder,
  raw : Json?,
) -> Map[String, Json] {
  match anthropic_stream_index(raw) {
    Some(index) if index >= 0 &&
      index < self.block_kinds.length() &&
      self.block_kinds[index] == "redacted_thinking" =>
      self.metadata_map({ "redactedData": self.block_redacted_data[index] })
    _ => Map([])
  }
}

///|
fn AnthropicStreamDecoder::v4_text_end_metadata(
  self : AnthropicStreamDecoder,
  raw : Json?,
) -> Map[String, Json] {
  match anthropic_stream_index(raw) {
    Some(index) if index >= 0 &&
      index < self.block_citations.length() &&
      self.block_citations[index].length() > 0 =>
      self.metadata_map({
        "citations": Json::array(
          [
            for citation in self.block_citations[index] => citation
          ],
        ),
      })
    _ => Map([])
  }
}

///|
fn AnthropicStreamDecoder::v4_tool_start(
  self : AnthropicStreamDecoder,
  id : String,
  tool_name : String,
  raw : Json?,
) -> @provider.LanguageModelV4StreamPart {
  match anthropic_stream_index(raw) {
    Some(index) if index >= 0 && index < self.block_kinds.length() =>
      @provider.V4ToolInputStart(
        id~,
        tool_name~,
        provider_executed=self.block_provider_executed[index],
        dynamic=self.block_dynamic[index],
        title=None,
        provider_metadata=Map([]),
      )
    _ =>
      @provider.V4ToolInputStart(
        id~,
        tool_name~,
        provider_executed=false,
        dynamic=false,
        title=None,
        provider_metadata=Map([]),
      )
  }
}

///|
/// Some Anthropic V4 parts have no legacy `StreamEvent` equivalent. Emit them
/// directly from the provider-native frame.
fn AnthropicStreamDecoder::v4_side_event(
  self : AnthropicStreamDecoder,
  raw : Json,
) -> @provider.LanguageModelV4StreamPart? {
  match raw {
    {
      "index": Number(index, ..),
      "delta": { "type": "signature_delta", "signature": String(signature), .. },
      ..
    } => {
      let block_index = index.to_int()
      if block_index >= 0 &&
        block_index < self.block_kinds.length() &&
        self.block_kinds[block_index] == "thinking" {
        Some(
          @provider.V4ReasoningDelta(
            id=self.block_id(block_index, "reasoning"),
            delta="",
            provider_metadata=self.metadata_map({ "signature": signature }),
          ),
        )
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Convert an Anthropic decoder event without dropping provider metadata from
/// the frame that produced it.
fn AnthropicStreamDecoder::v4_stream_part(
  self : AnthropicStreamDecoder,
  event : @provider.StreamEvent,
  raw : Json?,
) -> @provider.LanguageModelV4StreamPart? {
  match event {
    @provider.StreamStart => Some(@provider.V4StreamStart(warnings=[]))
    @provider.Warning(_) => None
    @provider.TextStart(id) =>
      Some(
        @provider.V4TextStart(
          id~,
          provider_metadata=self.v4_text_start_metadata(raw),
        ),
      )
    @provider.TextDelta(id~, delta~) =>
      Some(@provider.V4TextDelta(id~, delta~, provider_metadata=Map([])))
    @provider.TextEnd(id) =>
      Some(
        @provider.V4TextEnd(
          id~,
          provider_metadata=self.v4_text_end_metadata(raw),
        ),
      )
    @provider.ReasoningStart(id) =>
      Some(
        @provider.V4ReasoningStart(
          id~,
          provider_metadata=self.v4_reasoning_start_metadata(raw),
        ),
      )
    @provider.ReasoningDelta(id~, delta~) =>
      Some(@provider.V4ReasoningDelta(id~, delta~, provider_metadata=Map([])))
    @provider.ReasoningEnd(id) =>
      Some(@provider.V4ReasoningEnd(id~, provider_metadata=Map([])))
    @provider.ToolInputStart(id~, tool_name~) =>
      Some(self.v4_tool_start(id, tool_name, raw))
    @provider.ToolInputDelta(id~, delta~) =>
      Some(@provider.V4ToolInputDelta(id~, delta~, provider_metadata=Map([])))
    @provider.ToolInputEnd(id) =>
      Some(@provider.V4ToolInputEnd(id~, provider_metadata=Map([])))
    @provider.ToolCallReady(value) =>
      Some(
        @provider.V4ToolCallReady(
          @provider.LanguageModelV4ToolCall::from_tool_call(value),
        ),
      )
    @provider.ToolResultReady(value) =>
      Some(
        @provider.V4ToolResultReady(
          @provider.LanguageModelV4ToolResult::from_tool_result(value),
        ),
      )
    @provider.ToolApprovalRequestReady(value) =>
      Some(
        @provider.V4ToolApprovalRequestReady(
          @provider.LanguageModelV4ToolApprovalRequest::from_tool_approval_request(
            value,
          ),
        ),
      )
    @provider.FileReady(value) =>
      Some(
        @provider.V4FileReady(
          @provider.LanguageModelV4File::from_generated_file(value),
        ),
      )
    @provider.ReasoningFileReady(value) =>
      Some(
        @provider.V4ReasoningFileReady(
          @provider.LanguageModelV4ReasoningFile::from_generated_file(value),
        ),
      )
    @provider.SourceReady(value) =>
      Some(
        @provider.V4SourceReady(
          @provider.LanguageModelV4Source::from_generated_source(value),
        ),
      )
    @provider.CustomContentReady(value) =>
      Some(
        @provider.V4CustomContentReady({
          kind: value.kind,
          provider_metadata: @provider.copy_provider_metadata(
            value.provider_metadata,
          ),
        }),
      )
    @provider.ResponseMetadataReady(value) =>
      Some(@provider.V4ResponseMetadataReady(value))
    @provider.Finish(usage~, reason~) =>
      Some(
        @provider.V4Finish(
          usage=@provider.LanguageModelV4Usage::from_usage(usage),
          reason=@provider.LanguageModelV4FinishReason::from_finish_reason(
            reason,
          ),
          provider_metadata=Map([]),
        ),
      )
    @provider.Raw(value) => Some(@provider.V4Raw(value))
    @provider.StreamError(message) => Some(@provider.V4Error(message))
  }
}
