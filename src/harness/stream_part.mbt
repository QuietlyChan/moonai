///|
/// Workspace mutation surfaced by a coding-agent runtime.
pub(all) enum HarnessV1FileChangeKind {
  HarnessFileCreate
  HarnessFileModify
  HarnessFileDelete
} derive(Debug, Eq)

///|
/// Return the bridge spelling of a file mutation.
pub fn HarnessV1FileChangeKind::to_string(
  self : HarnessV1FileChangeKind,
) -> String {
  match self {
    HarnessFileCreate => "create"
    HarnessFileModify => "modify"
    HarnessFileDelete => "delete"
  }
}

///|
/// Decode a file mutation kind from a bridge frame.
pub fn HarnessV1FileChangeKind::from_string(
  value : String,
) -> HarnessV1FileChangeKind raise HarnessError {
  match value {
    "create" => HarnessFileCreate
    "modify" => HarnessFileModify
    "delete" => HarnessFileDelete
    _ => raise harness_error("Invalid harness file-change event: " + value)
  }
}

///|
/// Reason an underlying runtime compacted its context.
pub(all) enum HarnessV1CompactionTrigger {
  HarnessManualCompaction
  HarnessAutomaticCompaction
} derive(Debug, Eq)

///|
/// Return the bridge spelling of a compaction trigger.
pub fn HarnessV1CompactionTrigger::to_string(
  self : HarnessV1CompactionTrigger,
) -> String {
  match self {
    HarnessManualCompaction => "manual"
    HarnessAutomaticCompaction => "auto"
  }
}

///|
/// Decode a compaction trigger from a bridge frame.
pub fn HarnessV1CompactionTrigger::from_string(
  value : String,
) -> HarnessV1CompactionTrigger raise HarnessError {
  match value {
    "manual" => HarnessManualCompaction
    "auto" => HarnessAutomaticCompaction
    _ => raise harness_error("Invalid harness compaction trigger: " + value)
  }
}

///|
/// One event emitted by a Harness V1 adapter during a turn.
///
/// Tool calls, approvals, results, usage, and finish reasons reuse the
/// provider V4 primitives so high-level workflows do not need a second model
/// vocabulary.
pub(all) enum HarnessV1StreamPart {
  HarnessStreamStart(
    warnings~ : Array[HarnessV1CallWarning],
    model_id~ : String?
  )
  HarnessTextStart(id~ : String, harness_metadata~ : HarnessV1Metadata)
  HarnessTextDelta(
    id~ : String,
    delta~ : String,
    harness_metadata~ : HarnessV1Metadata
  )
  HarnessTextEnd(id~ : String, harness_metadata~ : HarnessV1Metadata)
  HarnessReasoningStart(id~ : String, harness_metadata~ : HarnessV1Metadata)
  HarnessReasoningDelta(
    id~ : String,
    delta~ : String,
    harness_metadata~ : HarnessV1Metadata
  )
  HarnessReasoningEnd(id~ : String, harness_metadata~ : HarnessV1Metadata)
  HarnessToolCall(
    call~ : @provider.LanguageModelV4ToolCall,
    native_name~ : String?
  )
  HarnessToolApprovalRequest(@provider.LanguageModelV4ToolApprovalRequest)
  HarnessToolResult(@provider.LanguageModelV4ToolResult)
  HarnessFinishStep(
    finish_reason~ : @provider.LanguageModelV4FinishReason,
    usage~ : @provider.LanguageModelV4Usage,
    harness_metadata~ : HarnessV1Metadata
  )
  HarnessFinish(
    finish_reason~ : @provider.LanguageModelV4FinishReason,
    total_usage~ : @provider.LanguageModelV4Usage,
    harness_metadata~ : HarnessV1Metadata
  )
  HarnessFileChange(
    event~ : HarnessV1FileChangeKind,
    path~ : String,
    harness_metadata~ : HarnessV1Metadata
  )
  HarnessCompaction(
    trigger~ : HarnessV1CompactionTrigger,
    summary~ : String,
    tokens_before~ : Int?,
    tokens_after~ : Int?,
    harness_metadata~ : HarnessV1Metadata
  )
  HarnessStreamError(error~ : Json)
  HarnessRaw(raw_value~ : Json)
} derive(Debug, Eq)

///|
/// Convert a harness event to the provider V4 stream vocabulary when the
/// provider contract has a lossless equivalent.
pub fn HarnessV1StreamPart::to_provider_stream_part(
  self : HarnessV1StreamPart,
) -> @provider.LanguageModelV4StreamPart? {
  match self {
    HarnessStreamStart(warnings~, ..) => {
      let result : Array[@provider.Warning] = []
      for warning in warnings {
        match warning {
          HarnessUnsupportedSetting(setting~, details~) =>
            result.push(
              @provider.Warning::Unsupported(
                feature="setting:" + setting,
                details=details.unwrap_or("Unsupported harness setting"),
              ),
            )
          HarnessUnsupportedTool(tool~, details~) =>
            result.push(
              @provider.Warning::Unsupported(
                feature="tool:" + tool,
                details=details.unwrap_or("Unsupported harness tool"),
              ),
            )
          HarnessOtherWarning(message~) =>
            result.push(@provider.Other(message~))
        }
      }
      Some(@provider.V4StreamStart(warnings=result))
    }
    HarnessTextStart(id~, harness_metadata~) =>
      Some(@provider.V4TextStart(id~, provider_metadata=harness_metadata))
    HarnessTextDelta(id~, delta~, harness_metadata~) =>
      Some(
        @provider.V4TextDelta(id~, delta~, provider_metadata=harness_metadata),
      )
    HarnessTextEnd(id~, harness_metadata~) =>
      Some(@provider.V4TextEnd(id~, provider_metadata=harness_metadata))
    HarnessReasoningStart(id~, harness_metadata~) =>
      Some(@provider.V4ReasoningStart(id~, provider_metadata=harness_metadata))
    HarnessReasoningDelta(id~, delta~, harness_metadata~) =>
      Some(
        @provider.V4ReasoningDelta(
          id~,
          delta~,
          provider_metadata=harness_metadata,
        ),
      )
    HarnessReasoningEnd(id~, harness_metadata~) =>
      Some(@provider.V4ReasoningEnd(id~, provider_metadata=harness_metadata))
    HarnessToolCall(call~, ..) => Some(@provider.V4ToolCallReady(call))
    HarnessToolApprovalRequest(request) =>
      Some(@provider.V4ToolApprovalRequestReady(request))
    HarnessToolResult(result) => Some(@provider.V4ToolResultReady(result))
    HarnessFinish(finish_reason~, total_usage~, harness_metadata~) =>
      Some(
        @provider.V4Finish(
          usage=total_usage,
          reason=finish_reason,
          provider_metadata=harness_metadata,
        ),
      )
    HarnessStreamError(error~) =>
      Some(
        @provider.V4Error(
          @provider.StreamErrorInfo::new(error.stringify(), data=error),
        ),
      )
    HarnessRaw(raw_value~) => Some(@provider.V4Raw(raw_value))
    HarnessFinishStep(..) | HarnessFileChange(..) | HarnessCompaction(..) =>
      None
  }
}
