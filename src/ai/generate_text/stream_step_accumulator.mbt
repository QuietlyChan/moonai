///|
priv enum StreamContentOrder {
  StreamTextOrder(String)
  StreamReasoningOrder(String)
  StreamReadyContent(@provider.LanguageModelV4Content)
}

///|
/// Mutable state for one provider stream. The provider contract emits
/// lifecycle parts, while the high-level workflow needs the same ordered
/// completed content shape that `generateText` receives from `do_generate`.
priv struct StreamStepAccumulator {
  order : Array[StreamContentOrder]
  text : Map[String, StringBuilder]
  text_metadata : Map[String, Map[String, Json]]
  reasoning : Map[String, StringBuilder]
  reasoning_metadata : Map[String, Map[String, Json]]
  warnings : Array[@provider.Warning]
  usage : Ref[@provider.LanguageModelV4Usage]
  finish_reason : Ref[@provider.LanguageModelV4FinishReason]
  provider_metadata : Ref[Map[String, Json]]
  response : Ref[@provider.ResponseMetadata?]
}

///|
fn StreamStepAccumulator::new() -> StreamStepAccumulator {
  {
    order: [],
    text: Map([]),
    text_metadata: Map([]),
    reasoning: Map([]),
    reasoning_metadata: Map([]),
    warnings: [],
    usage: Ref(@provider.LanguageModelV4Usage::unknown()),
    finish_reason: Ref(@provider.LanguageModelV4FinishReason::unknown()),
    provider_metadata: Ref(Map([])),
    response: Ref(None),
  }
}

///|
fn merge_stream_part_metadata(
  values : Map[String, Map[String, Json]],
  id : String,
  metadata : Map[String, Json],
) -> Unit {
  guard metadata.length() > 0 else { return }
  values[id] = @provider.merge_provider_metadata(
    values.get(id).unwrap_or(Map([])),
    metadata,
  )
}

///|
fn StreamStepAccumulator::ensure_text(
  self : StreamStepAccumulator,
  id : String,
  metadata : Map[String, Json],
) -> StringBuilder {
  merge_stream_part_metadata(self.text_metadata, id, metadata)
  match self.text.get(id) {
    Some(value) => value
    None => {
      let value = StringBuilder::new()
      self.text[id] = value
      self.order.push(StreamTextOrder(id))
      value
    }
  }
}

///|
fn StreamStepAccumulator::ensure_reasoning(
  self : StreamStepAccumulator,
  id : String,
  metadata : Map[String, Json],
) -> StringBuilder {
  merge_stream_part_metadata(self.reasoning_metadata, id, metadata)
  match self.reasoning.get(id) {
    Some(value) => value
    None => {
      let value = StringBuilder::new()
      self.reasoning[id] = value
      self.order.push(StreamReasoningOrder(id))
      value
    }
  }
}

///|
fn StreamStepAccumulator::push_ready_content(
  self : StreamStepAccumulator,
  content : @provider.LanguageModelV4Content,
) -> Unit {
  self.order.push(StreamReadyContent(content))
}

///|
fn StreamStepAccumulator::process(
  self : StreamStepAccumulator,
  event : @provider.LanguageModelV4StreamPart,
) -> Unit {
  match event {
    @provider.V4StreamStart(warnings~) =>
      for warning in warnings {
        self.warnings.push(warning)
      }
    @provider.V4TextStart(id~, provider_metadata~) =>
      self.ensure_text(id, provider_metadata) |> ignore
    @provider.V4TextDelta(id~, delta~, provider_metadata~) =>
      self.ensure_text(id, provider_metadata).write_string(delta)
    @provider.V4TextEnd(id~, provider_metadata~) =>
      self.ensure_text(id, provider_metadata) |> ignore
    @provider.V4ReasoningStart(id~, provider_metadata~) =>
      self.ensure_reasoning(id, provider_metadata) |> ignore
    @provider.V4ReasoningDelta(id~, delta~, provider_metadata~) =>
      self.ensure_reasoning(id, provider_metadata).write_string(delta)
    @provider.V4ReasoningEnd(id~, provider_metadata~) =>
      self.ensure_reasoning(id, provider_metadata) |> ignore
    @provider.V4ToolCallReady(value) =>
      self.push_ready_content(@provider.V4ToolCallOutput(value))
    @provider.V4ToolResultReady(value) =>
      self.push_ready_content(@provider.V4ToolResultOutput(value))
    @provider.V4ToolApprovalRequestReady(value) =>
      self.push_ready_content(@provider.V4ToolApprovalRequestOutput(value))
    @provider.V4FileReady(value) =>
      self.push_ready_content(@provider.V4FileOutput(value))
    @provider.V4ReasoningFileReady(value) =>
      self.push_ready_content(@provider.V4ReasoningFileOutput(value))
    @provider.V4SourceReady(value) =>
      self.push_ready_content(@provider.V4SourceOutput(value))
    @provider.V4CustomContentReady(value) =>
      self.push_ready_content(@provider.V4CustomOutput(value))
    @provider.V4ResponseMetadataReady(value) =>
      self.response.val = @provider.merge_optional_response_metadata(
        self.response.val,
        Some(value),
      )
    @provider.V4Finish(usage~, reason~, provider_metadata~) => {
      self.usage.val = usage
      self.finish_reason.val = reason
      self.provider_metadata.val = @provider.copy_provider_metadata(
        provider_metadata,
      )
    }
    @provider.V4ToolInputStart(..)
    | @provider.V4ToolInputDelta(..)
    | @provider.V4ToolInputEnd(..)
    | @provider.V4Raw(_)
    | @provider.V4Error(_) => ()
  }
}

///|
fn StreamStepAccumulator::content(
  self : StreamStepAccumulator,
) -> Array[@provider.LanguageModelV4Content] {
  let content : Array[@provider.LanguageModelV4Content] = []
  for item in self.order {
    match item {
      StreamTextOrder(id) =>
        content.push(
          @provider.LanguageModelV4Content::text(
            self.text[id].to_string(),
            provider_metadata=self.text_metadata.get(id).unwrap_or(Map([])),
          ),
        )
      StreamReasoningOrder(id) =>
        content.push(
          @provider.LanguageModelV4Content::reasoning(
            self.reasoning[id].to_string(),
            provider_metadata=self.reasoning_metadata.get(id).unwrap_or(Map([])),
          ),
        )
      StreamReadyContent(value) => content.push(value)
    }
  }
  content
}

///|
fn StreamStepAccumulator::provider_result(
  self : StreamStepAccumulator,
  stream_result : @provider.LanguageModelV4StreamResult,
) -> @provider.LanguageModelV4GenerateResult {
  {
    content: self.content(),
    finish_reason: self.finish_reason.val,
    usage: self.usage.val,
    provider_metadata: @provider.copy_provider_metadata(
      self.provider_metadata.val,
    ),
    request: stream_result.request,
    response: @provider.merge_optional_response_metadata(
      stream_result.response,
      self.response.val,
    ),
    warnings: @provider.copy_warnings(self.warnings),
  }
}
