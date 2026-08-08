///|
/// Mutable state owned by one OpenAI Responses SSE attempt. Rebuilding the
/// runtime on retry prevents partially decoded metadata, tools, and content
/// from leaking into the next HTTP response.
priv struct OpenAIResponsesStreamRuntime {
  stream_guard : OpenAIResponsesStreamGuard
  decoder : @protocol.OpenResponsesStreamDecoder
  v4_metadata : OpenAIResponsesV4StreamMetadata
  emit_raw_chunks : Bool
  mut raw_event : Json?
}

///|
fn openai_responses_stream_runtime(
  provider_name : String,
  tool_name_mapping : @provider_utils.ToolNameMapping,
  shell_provider_executed : Bool,
  emit_raw_chunks : Bool,
  store~ : Bool,
  id_generator~ : @provider_utils.IdGenerator,
  approval_tool_call_ids~ : Map[String, String],
  web_search_tool_name? : String,
) -> OpenAIResponsesStreamRuntime {
  let stream_guard = OpenAIResponsesStreamGuard::new()
  let (record_metadata, build_provider_metadata) = openai_responses_stream_metadata(
    provider_name,
  )
  let hosted_decoder = OpenAIResponsesHostedStreamDecoder::new(
    provider_name,
    tool_name_mapping,
    shell_provider_executed,
    id_generator~,
    approval_tool_call_ids~,
    web_search_tool_name?,
  )
  let decoder = @protocol.OpenResponsesStreamDecoder::new(
    // Raw protocol frames feed the V4 metadata transform even when callers do
    // not request `V4Raw` parts.
    include_raw_chunks=true,
    progressive_tool_calls=true,
    emit_failed_error=true,
    split_reasoning_summary_parts=true,
    provider_name~,
    id_generator~,
    observe_json=record_metadata,
    validate_json=json => stream_guard.validate(json),
    observe_events=json => hosted_decoder.observe(json),
    build_provider_metadata~,
    build_content=() => hosted_decoder.content(),
    use_built_content=true,
    has_extra_tool_calls=() => hosted_decoder.has_client_calls(),
    build_tool_metadata=(item_id, item) => {
      openai_responses_tool_item_metadata(provider_name, item_id, item)
    },
    convert_v4_usage=openai_responses_v4_usage,
  )
  {
    stream_guard,
    decoder,
    v4_metadata: OpenAIResponsesV4StreamMetadata::new(
      provider_name,
      store~,
      shell_provider_executed~,
    ),
    emit_raw_chunks,
    raw_event: None,
  }
}

///|
fn OpenAIResponsesStreamRuntime::v4_batch(
  self : OpenAIResponsesStreamRuntime,
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
        for part in self.v4_metadata.observe_raw(value) {
          events.push(part)
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
        match self.v4_metadata.v4_stream_part(other, self.raw_event) {
          Some(part) => events.push(part)
          None => ()
        }
    }
  }
  { events, consumed_event: batch.consumed_event, done: batch.done }
}

///|
fn OpenAIResponsesStreamRuntime::feed_line(
  self : OpenAIResponsesStreamRuntime,
  raw : String,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  self.v4_batch(self.decoder.feed_line(raw))
}

///|
fn OpenAIResponsesStreamRuntime::flush_buffered(
  self : OpenAIResponsesStreamRuntime,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] raise {
  self.v4_batch(self.decoder.flush_buffered())
}

///|
/// Finish the shared Open Responses transform after a normal transport EOF.
fn OpenAIResponsesStreamRuntime::finish_stream(
  self : OpenAIResponsesStreamRuntime,
) -> @provider_utils.SseDecodeBatch[@provider.LanguageModelV4StreamPart] {
  self.v4_batch(self.decoder.finish_stream())
}

///|
fn OpenAIResponsesStreamRuntime::response_metadata_snapshot(
  self : OpenAIResponsesStreamRuntime,
) -> @provider.ResponseMetadata? {
  self.decoder.response_metadata_snapshot()
}

///|
fn openai_responses_stream_runtime_with_policy(
  create_runtime : () -> OpenAIResponsesStreamRuntime,
) -> (Ref[OpenAIResponsesStreamRuntime], @provider_utils.SseStreamStartPolicy) raise {
  let runtime = Ref(create_runtime())
  let start_policy = @provider_utils.SseStreamStartPolicy::new(
    is_accepted=() => runtime.val.stream_guard.is_accepted(),
    is_output=() => runtime.val.stream_guard.has_output(),
    on_started=() => runtime.val.stream_guard.mark_started(),
    on_retry=() => runtime.val = create_runtime(),
  )
  (runtime, start_policy)
}
