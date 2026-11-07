///|
/// Values accepted by OpenAI's `logprobs` option.
///
/// `Enabled` requests generated-token log probabilities, while `Top` requests
/// the top N candidates at each position. `Disabled` is useful when composing
/// an options value programmatically and is encoded as `false`.
#derive(Debug, Eq)
pub(all) enum OpenAILogprobs {
  OpenAILogprobsEnabled
  OpenAILogprobsDisabled
  OpenAILogprobsTop(Int32)
}

///|
/// Request generated-token log probabilities.
pub fn OpenAILogprobs::enabled() -> OpenAILogprobs {
  OpenAILogprobsEnabled
}

///|
/// Explicitly disable generated-token log probabilities.
pub fn OpenAILogprobs::disabled() -> OpenAILogprobs {
  OpenAILogprobsDisabled
}

///|
/// Request the top `value` candidate log probabilities at each position.
pub fn OpenAILogprobs::top(value : Int32) -> OpenAILogprobs raise {
  guard value >= 0 else { fail("OpenAI logprobs must be non-negative") }
  OpenAILogprobsTop(value)
}

///|
fn OpenAILogprobs::to_json(self : OpenAILogprobs) -> Json {
  match self {
    OpenAILogprobsEnabled => Json::boolean(true)
    OpenAILogprobsDisabled => Json::boolean(false)
    OpenAILogprobsTop(value) => Json::number(value.to_double())
  }
}

///|
/// Prompt-cache mode for GPT-5.6 and later models.
#derive(Debug, Eq)
pub(all) enum OpenAIPromptCacheMode {
  OpenAIPromptCacheImplicit
  OpenAIPromptCacheExplicit
}

///|
fn OpenAIPromptCacheMode::wire_name(self : OpenAIPromptCacheMode) -> String {
  match self {
    OpenAIPromptCacheImplicit => "implicit"
    OpenAIPromptCacheExplicit => "explicit"
  }
}

///|
/// Prompt-cache TTL currently supported by OpenAI.
#derive(Debug, Eq)
pub(all) enum OpenAIPromptCacheTtl {
  OpenAIPromptCacheThirtyMinutes
}

///|
fn OpenAIPromptCacheTtl::wire_name(self : OpenAIPromptCacheTtl) -> String {
  match self {
    OpenAIPromptCacheThirtyMinutes => "30m"
  }
}

///|
/// Structured prompt-cache settings shared by Responses and Chat models.
#derive(Debug, Eq)
pub(all) struct OpenAIPromptCacheOptions {
  mode : OpenAIPromptCacheMode?
  ttl : OpenAIPromptCacheTtl?
}

///|
/// Construct prompt-cache settings.
pub fn OpenAIPromptCacheOptions::new(
  mode? : OpenAIPromptCacheMode,
  ttl? : OpenAIPromptCacheTtl,
) -> OpenAIPromptCacheOptions {
  { mode, ttl, }
}

///|
fn OpenAIPromptCacheOptions::to_json(self : OpenAIPromptCacheOptions) -> Json {
  Json::object(
    Map(
      [
        ..if self.mode is Some(value) {
          [("mode", Json::string(value.wire_name()))]
        },
        ..if self.ttl is Some(value) {
          [("ttl", Json::string(value.wire_name()))]
        },
      ],
    ),
  )
}

///|
/// OpenAI service tier selection.
#derive(Debug, Eq)
pub(all) enum OpenAIServiceTier {
  OpenAIServiceTierAuto
  OpenAIServiceTierFlex
  OpenAIServiceTierPriority
  OpenAIServiceTierFast
  OpenAIServiceTierUltrafast
  OpenAIServiceTierDefault
}

///|
fn OpenAIServiceTier::wire_name(self : OpenAIServiceTier) -> String {
  match self {
    OpenAIServiceTierAuto => "auto"
    OpenAIServiceTierFlex => "flex"
    OpenAIServiceTierPriority => "priority"
    // 'fast' is OpenAI's newer name for the 'priority' tier.
    OpenAIServiceTierFast => "fast"
    // 'ultrafast' is access-controlled and limited to gpt-5.6-sol.
    OpenAIServiceTierUltrafast => "ultrafast"
    OpenAIServiceTierDefault => "default"
  }
}

///|
/// Reasoning mode available on the newest OpenAI reasoning models.
#derive(Debug, Eq)
pub(all) enum OpenAIReasoningMode {
  OpenAIReasoningStandard
  OpenAIReasoningPro
}

///|
fn OpenAIReasoningMode::wire_name(self : OpenAIReasoningMode) -> String {
  match self {
    OpenAIReasoningStandard => "standard"
    OpenAIReasoningPro => "pro"
  }
}

///|
/// Reasoning context selection for Responses requests.
#derive(Debug, Eq)
pub(all) enum OpenAIReasoningContext {
  OpenAIReasoningContextAuto
  OpenAIReasoningContextCurrentTurn
  OpenAIReasoningContextAllTurns
}

///|
fn OpenAIReasoningContext::wire_name(self : OpenAIReasoningContext) -> String {
  match self {
    OpenAIReasoningContextAuto => "auto"
    OpenAIReasoningContextCurrentTurn => "current_turn"
    OpenAIReasoningContextAllTurns => "all_turns"
  }
}

///|
/// Text verbosity for OpenAI Responses and Chat requests.
#derive(Debug, Eq)
pub(all) enum OpenAITextVerbosity {
  OpenAITextVerbosityLow
  OpenAITextVerbosityMedium
  OpenAITextVerbosityHigh
}

///|
fn OpenAITextVerbosity::wire_name(self : OpenAITextVerbosity) -> String {
  match self {
    OpenAITextVerbosityLow => "low"
    OpenAITextVerbosityMedium => "medium"
    OpenAITextVerbosityHigh => "high"
  }
}

///|
/// Retention policy for OpenAI prompt caching.
#derive(Debug, Eq)
pub(all) enum OpenAIPromptCacheRetention {
  OpenAIPromptCacheInMemory
  OpenAIPromptCacheTwentyFourHours
}

///|
fn OpenAIPromptCacheRetention::wire_name(
  self : OpenAIPromptCacheRetention,
) -> String {
  match self {
    OpenAIPromptCacheInMemory => "in_memory"
    OpenAIPromptCacheTwentyFourHours => "24h"
  }
}

///|
/// System-role handling for OpenAI Chat and Responses models.
#derive(Debug, Eq)
pub(all) enum OpenAISystemMessageMode {
  OpenAISystemMessageSystem
  OpenAISystemMessageDeveloper
  OpenAISystemMessageRemove
}

///|
fn OpenAISystemMessageMode::wire_name(self : OpenAISystemMessageMode) -> String {
  match self {
    OpenAISystemMessageSystem => "system"
    OpenAISystemMessageDeveloper => "developer"
    OpenAISystemMessageRemove => "remove"
  }
}

///|
/// Responses output truncation behavior.
#derive(Debug, Eq)
pub(all) enum OpenAITruncation {
  OpenAITruncationAuto
  OpenAITruncationDisabled
}

///|
fn OpenAITruncation::wire_name(self : OpenAITruncation) -> String {
  match self {
    OpenAITruncationAuto => "auto"
    OpenAITruncationDisabled => "disabled"
  }
}

///|
/// An item in Responses server-side context management.
#derive(Debug, Eq)
pub(all) enum OpenAIContextManagement {
  OpenAIContextCompaction(compact_threshold~ : Double)
}

///|
/// Construct a server-side compaction setting.
pub fn OpenAIContextManagement::compaction(
  compact_threshold~ : Double,
) -> OpenAIContextManagement raise {
  guard compact_threshold >= 0.0 else {
    fail("OpenAI context compaction threshold must be non-negative")
  }
  OpenAIContextCompaction(compact_threshold~)
}

///|
fn OpenAIContextManagement::to_json(self : OpenAIContextManagement) -> Json {
  match self {
    OpenAIContextCompaction(compact_threshold~) =>
      {
        "type": "compaction",
        "compactThreshold": Json::number(compact_threshold),
      }
  }
}

///|
/// Mode used by Responses `allowed_tools`.
#derive(Debug, Eq)
pub(all) enum OpenAIAllowedToolsMode {
  OpenAIAllowedToolsAuto
  OpenAIAllowedToolsRequired
}

///|
fn OpenAIAllowedToolsMode::wire_name(self : OpenAIAllowedToolsMode) -> String {
  match self {
    OpenAIAllowedToolsAuto => "auto"
    OpenAIAllowedToolsRequired => "required"
  }
}

///|
/// Restrict the callable tools while preserving the complete tools list.
#derive(Debug, Eq)
pub(all) struct OpenAIAllowedTools {
  tool_names : Array[String]
  mode : OpenAIAllowedToolsMode?
}

///|
/// Construct an allowed-tools restriction.
pub fn OpenAIAllowedTools::new(
  tool_names~ : Array[String],
  mode? : OpenAIAllowedToolsMode,
) -> OpenAIAllowedTools raise {
  guard tool_names.length() > 0 else {
    fail("OpenAI allowed_tools requires at least one tool name")
  }
  { tool_names: tool_names.copy(), mode, }
}

///|
fn OpenAIAllowedTools::to_json(self : OpenAIAllowedTools) -> Json {
  Json::object(
    Map(
      [
        (
          "toolNames",
          Json::array([ for name in self.tool_names => Json::string(name) ]),
        ),
        ..if self.mode is Some(value) {
          [("mode", Json::string(value.wire_name()))]
        },
      ],
    ),
  )
}

///|
/// One OpenAI Responses `include` value.
#derive(Debug, Eq)
pub(all) enum OpenAIResponsesInclude {
  OpenAIIncludeReasoningEncryptedContent
  OpenAIIncludeFileSearchCallResults
  OpenAIIncludeWebSearchCallResults
  OpenAIIncludeWebSearchCallActionSources
  OpenAIIncludeCodeInterpreterCallOutputs
  OpenAIIncludeComputerCallOutputImageUrl
  OpenAIIncludeMessageInputImageImageUrl
  OpenAIIncludeMessageOutputTextLogprobs
}

///|
fn OpenAIResponsesInclude::wire_name(self : OpenAIResponsesInclude) -> String {
  match self {
    OpenAIIncludeReasoningEncryptedContent => "reasoning.encrypted_content"
    OpenAIIncludeFileSearchCallResults => "file_search_call.results"
    OpenAIIncludeWebSearchCallResults => "web_search_call.results"
    OpenAIIncludeWebSearchCallActionSources => "web_search_call.action.sources"
    OpenAIIncludeCodeInterpreterCallOutputs => "code_interpreter_call.outputs"
    OpenAIIncludeComputerCallOutputImageUrl =>
      "computer_call_output.output.image_url"
    OpenAIIncludeMessageInputImageImageUrl => "message.input_image.image_url"
    OpenAIIncludeMessageOutputTextLogprobs => "message.output_text.logprobs"
  }
}

///|
fn openai_typed_namespace(
  provider_name : String,
  fields : Map[String, Json],
) -> Map[String, Json] {
  Map([(provider_name, Json::object(fields))])
}

///|
fn openai_metadata_json(values : Map[String, String]) -> Json {
  let fields : Map[String, Json] = Map([])
  for entry in values.iter2() {
    fields[entry.0] = Json::string(entry.1)
  }
  Json::object(fields)
}

///|
/// Typed provider options for the official OpenAI Responses language model.
///
/// This mirrors AI SDK's `OpenAILanguageModelResponsesOptions`. Standard
/// generation controls remain on `@provider.ChatCallOptions`; this type only
/// contains OpenAI-specific fields.
#derive(Debug)
pub(all) struct OpenAILanguageModelResponsesOptions {
  conversation : String?
  include_values : Array[OpenAIResponsesInclude]?
  instructions : String?
  logprobs : OpenAILogprobs?
  max_tool_calls : Int32?
  metadata : Json?
  parallel_tool_calls : Bool?
  previous_response_id : String?
  prompt_cache_key : String?
  prompt_cache_options : OpenAIPromptCacheOptions?
  prompt_cache_retention : OpenAIPromptCacheRetention?
  reasoning_effort : String?
  reasoning_mode : OpenAIReasoningMode?
  reasoning_context : OpenAIReasoningContext?
  reasoning_summary : String?
  safety_identifier : String?
  service_tier : OpenAIServiceTier?
  store : Bool?
  pass_through_unsupported_files : Bool?
  strict_json_schema : Bool?
  text_verbosity : OpenAITextVerbosity?
  truncation : OpenAITruncation?
  user : String?
  system_message_mode : OpenAISystemMessageMode?
  force_reasoning : Bool?
  context_management : Array[OpenAIContextManagement]?
  allowed_tools : OpenAIAllowedTools?
}

///|
/// Construct typed Responses options. Values are encoded in the provider
/// namespace by `to_provider_options`.
pub fn OpenAILanguageModelResponsesOptions::new(
  conversation? : String,
  include_values? : Array[OpenAIResponsesInclude],
  instructions? : String,
  logprobs? : OpenAILogprobs,
  max_tool_calls? : Int32,
  metadata? : Json,
  parallel_tool_calls? : Bool,
  previous_response_id? : String,
  prompt_cache_key? : String,
  prompt_cache_options? : OpenAIPromptCacheOptions,
  prompt_cache_retention? : OpenAIPromptCacheRetention,
  reasoning_effort? : String,
  reasoning_mode? : OpenAIReasoningMode,
  reasoning_context? : OpenAIReasoningContext,
  reasoning_summary? : String,
  safety_identifier? : String,
  service_tier? : OpenAIServiceTier,
  store? : Bool,
  pass_through_unsupported_files? : Bool,
  strict_json_schema? : Bool,
  text_verbosity? : OpenAITextVerbosity,
  truncation? : OpenAITruncation,
  user? : String,
  system_message_mode? : OpenAISystemMessageMode,
  force_reasoning? : Bool,
  context_management? : Array[OpenAIContextManagement],
  allowed_tools? : OpenAIAllowedTools,
) -> OpenAILanguageModelResponsesOptions raise {
  if max_tool_calls is Some(value) && value < 0 {
    fail("OpenAI max_tool_calls must be non-negative")
  }
  if logprobs is Some(OpenAILogprobsTop(value)) && (value < 1 || value > 20) {
    fail("OpenAI Responses logprobs must be between 1 and 20")
  }
  {
    conversation,
    include_values,
    instructions,
    logprobs,
    max_tool_calls,
    metadata,
    parallel_tool_calls,
    previous_response_id,
    prompt_cache_key,
    prompt_cache_options,
    prompt_cache_retention,
    reasoning_effort,
    reasoning_mode,
    reasoning_context,
    reasoning_summary,
    safety_identifier,
    service_tier,
    store,
    pass_through_unsupported_files,
    strict_json_schema,
    text_verbosity,
    truncation,
    user,
    system_message_mode,
    force_reasoning,
    context_management,
    allowed_tools,
  }
}

///|
/// Convert typed Responses options to a provider-options namespace.
pub fn OpenAILanguageModelResponsesOptions::to_provider_options(
  self : OpenAILanguageModelResponsesOptions,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map(
    [
      ..if self.conversation is Some(value) {
        [("conversation", Json::string(value))]
      },
      ..if self.include_values is Some(values) {
        [
          (
            "include",
            Json::array(
              [
                for value in values => Json::string(value.wire_name())
              ],
            ),
          ),
        ]
      },
      ..if self.instructions is Some(value) {
        [("instructions", Json::string(value))]
      },
      ..if self.logprobs is Some(value) {
        [("logprobs", value.to_json())]
      },
      ..if self.max_tool_calls is Some(value) {
        [("maxToolCalls", Json::number(value.to_double()))]
      },
      ..if self.metadata is Some(value) {
        [("metadata", value)]
      },
      ..if self.parallel_tool_calls is Some(value) {
        [("parallelToolCalls", Json::boolean(value))]
      },
      ..if self.previous_response_id is Some(value) {
        [("previousResponseId", Json::string(value))]
      },
      ..if self.prompt_cache_key is Some(value) {
        [("promptCacheKey", Json::string(value))]
      },
      ..if self.prompt_cache_options is Some(value) {
        [("promptCacheOptions", value.to_json())]
      },
      ..if self.prompt_cache_retention is Some(value) {
        [("promptCacheRetention", Json::string(value.wire_name()))]
      },
      ..if self.reasoning_effort is Some(value) {
        [("reasoningEffort", Json::string(value))]
      },
      ..if self.reasoning_mode is Some(value) {
        [("reasoningMode", Json::string(value.wire_name()))]
      },
      ..if self.reasoning_context is Some(value) {
        [("reasoningContext", Json::string(value.wire_name()))]
      },
      ..if self.reasoning_summary is Some(value) {
        [("reasoningSummary", Json::string(value))]
      },
      ..if self.safety_identifier is Some(value) {
        [("safetyIdentifier", Json::string(value))]
      },
      ..if self.service_tier is Some(value) {
        [("serviceTier", Json::string(value.wire_name()))]
      },
      ..if self.store is Some(value) {
        [("store", Json::boolean(value))]
      },
      ..if self.pass_through_unsupported_files is Some(value) {
        [("passThroughUnsupportedFiles", Json::boolean(value))]
      },
      ..if self.strict_json_schema is Some(value) {
        [("strictJsonSchema", Json::boolean(value))]
      },
      ..if self.text_verbosity is Some(value) {
        [("textVerbosity", Json::string(value.wire_name()))]
      },
      ..if self.truncation is Some(value) {
        [("truncation", Json::string(value.wire_name()))]
      },
      ..if self.user is Some(value) {
        [("user", Json::string(value))]
      },
      ..if self.system_message_mode is Some(value) {
        [("systemMessageMode", Json::string(value.wire_name()))]
      },
      ..if self.force_reasoning is Some(value) {
        [("forceReasoning", Json::boolean(value))]
      },
      ..if self.context_management is Some(values) {
        [
          (
            "contextManagement",
            Json::array([ for value in values => value.to_json() ]),
          ),
        ]
      },
      ..if self.allowed_tools is Some(value) {
        [("allowedTools", value.to_json())]
      },
    ],
  )
  openai_typed_namespace(provider_name, fields)
}

///|
/// Typed provider options for the official OpenAI Chat Completions model.
#derive(Debug)
pub(all) struct OpenAILanguageModelChatOptions {
  logit_bias : Map[String, Double]?
  logprobs : OpenAILogprobs?
  parallel_tool_calls : Bool?
  user : String?
  reasoning_effort : String?
  max_completion_tokens : Int32?
  store : Bool?
  metadata : Map[String, String]?
  prediction : Json?
  service_tier : OpenAIServiceTier?
  strict_json_schema : Bool?
  text_verbosity : OpenAITextVerbosity?
  prompt_cache_key : String?
  prompt_cache_options : OpenAIPromptCacheOptions?
  prompt_cache_retention : OpenAIPromptCacheRetention?
  safety_identifier : String?
  system_message_mode : OpenAISystemMessageMode?
  force_reasoning : Bool?
}

///|
/// Construct typed Chat Completions options.
pub fn OpenAILanguageModelChatOptions::new(
  logit_bias? : Map[String, Double],
  logprobs? : OpenAILogprobs,
  parallel_tool_calls? : Bool,
  user? : String,
  reasoning_effort? : String,
  max_completion_tokens? : Int32,
  store? : Bool,
  metadata? : Map[String, String],
  prediction? : Json,
  service_tier? : OpenAIServiceTier,
  strict_json_schema? : Bool,
  text_verbosity? : OpenAITextVerbosity,
  prompt_cache_key? : String,
  prompt_cache_options? : OpenAIPromptCacheOptions,
  prompt_cache_retention? : OpenAIPromptCacheRetention,
  safety_identifier? : String,
  system_message_mode? : OpenAISystemMessageMode,
  force_reasoning? : Bool,
) -> OpenAILanguageModelChatOptions raise {
  if max_completion_tokens is Some(value) && value < 1 {
    fail("OpenAI max_completion_tokens must be greater than or equal to 1")
  }
  {
    logit_bias,
    logprobs,
    parallel_tool_calls,
    user,
    reasoning_effort,
    max_completion_tokens,
    store,
    metadata,
    prediction,
    service_tier,
    strict_json_schema,
    text_verbosity,
    prompt_cache_key,
    prompt_cache_options,
    prompt_cache_retention,
    safety_identifier,
    system_message_mode,
    force_reasoning,
  }
}

///|
/// Convert typed Chat Completions options to a provider-options namespace.
pub fn OpenAILanguageModelChatOptions::to_provider_options(
  self : OpenAILanguageModelChatOptions,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  let logit_bias = match self.logit_bias {
    Some(value) => {
      let fields : Map[String, Json] = Map([])
      for entry in value.iter2() {
        fields[entry.0] = Json::number(entry.1)
      }
      Some(Json::object(fields))
    }
    None => None
  }
  let fields : Map[String, Json] = Map(
    [
      ..if logit_bias is Some(value) {
        [("logitBias", value)]
      },
      ..if self.logprobs is Some(value) {
        [("logprobs", value.to_json())]
      },
      ..if self.parallel_tool_calls is Some(value) {
        [("parallelToolCalls", Json::boolean(value))]
      },
      ..if self.user is Some(value) {
        [("user", Json::string(value))]
      },
      ..if self.reasoning_effort is Some(value) {
        [("reasoningEffort", Json::string(value))]
      },
      ..if self.max_completion_tokens is Some(value) {
        [("maxCompletionTokens", Json::number(value.to_double()))]
      },
      ..if self.store is Some(value) {
        [("store", Json::boolean(value))]
      },
      ..if self.metadata is Some(value) {
        [("metadata", openai_metadata_json(value))]
      },
      ..if self.prediction is Some(value) {
        [("prediction", value)]
      },
      ..if self.service_tier is Some(value) {
        [("serviceTier", Json::string(value.wire_name()))]
      },
      ..if self.strict_json_schema is Some(value) {
        [("strictJsonSchema", Json::boolean(value))]
      },
      ..if self.text_verbosity is Some(value) {
        [("textVerbosity", Json::string(value.wire_name()))]
      },
      ..if self.prompt_cache_key is Some(value) {
        [("promptCacheKey", Json::string(value))]
      },
      ..if self.prompt_cache_options is Some(value) {
        [("promptCacheOptions", value.to_json())]
      },
      ..if self.prompt_cache_retention is Some(value) {
        [("promptCacheRetention", Json::string(value.wire_name()))]
      },
      ..if self.safety_identifier is Some(value) {
        [("safetyIdentifier", Json::string(value))]
      },
      ..if self.system_message_mode is Some(value) {
        [("systemMessageMode", Json::string(value.wire_name()))]
      },
      ..if self.force_reasoning is Some(value) {
        [("forceReasoning", Json::boolean(value))]
      },
    ],
  )
  openai_typed_namespace(provider_name, fields)
}

///|
/// Typed provider options for the official OpenAI legacy Completion model.
#derive(Debug)
pub(all) struct OpenAILanguageModelCompletionOptions {
  echo : Bool?
  logit_bias : Map[String, Double]?
  suffix : String?
  user : String?
  logprobs : OpenAILogprobs?
}

///|
/// Construct typed legacy Completion options.
pub fn OpenAILanguageModelCompletionOptions::new(
  echo? : Bool,
  logit_bias? : Map[String, Double],
  suffix? : String,
  user? : String,
  logprobs? : OpenAILogprobs,
) -> OpenAILanguageModelCompletionOptions {
  { echo, logit_bias, suffix, user, logprobs, }
}

///|
/// Convert typed Completion options to a provider-options namespace.
pub fn OpenAILanguageModelCompletionOptions::to_provider_options(
  self : OpenAILanguageModelCompletionOptions,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  let logit_bias = match self.logit_bias {
    Some(value) => {
      let fields : Map[String, Json] = Map([])
      for entry in value.iter2() {
        fields[entry.0] = Json::number(entry.1)
      }
      Some(Json::object(fields))
    }
    None => None
  }
  let fields : Map[String, Json] = Map(
    [
      ..if self.echo is Some(value) {
        [("echo", Json::boolean(value))]
      },
      ..if logit_bias is Some(value) {
        [("logitBias", value)]
      },
      ..if self.suffix is Some(value) {
        [("suffix", Json::string(value))]
      },
      ..if self.user is Some(value) {
        [("user", Json::string(value))]
      },
      ..if self.logprobs is Some(value) {
        [("logprobs", value.to_json())]
      },
    ],
  )
  openai_typed_namespace(provider_name, fields)
}

///|
/// Typed provider options for OpenAI embedding models.
#derive(Debug, Eq)
pub(all) struct OpenAIEmbeddingModelOptions {
  dimensions : Int32?
  user : String?
}

///|
/// Construct typed OpenAI embedding options.
pub fn OpenAIEmbeddingModelOptions::new(
  dimensions? : Int32,
  user? : String,
) -> OpenAIEmbeddingModelOptions raise {
  if dimensions is Some(value) && value < 1 {
    fail("OpenAI embedding dimensions must be greater than or equal to 1")
  }
  { dimensions, user, }
}

///|
/// Convert typed embedding options to a provider-options namespace.
pub fn OpenAIEmbeddingModelOptions::to_provider_options(
  self : OpenAIEmbeddingModelOptions,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  openai_typed_namespace(
    provider_name,
    Map(
      [
        ..if self.dimensions is Some(value) {
          [("dimensions", Json::number(value.to_double()))]
        },
        ..if self.user is Some(value) {
          [("user", Json::string(value))]
        },
      ],
    ),
  )
}

///|
/// Quality setting for OpenAI image generation.
#derive(Debug, Eq)
pub(all) enum OpenAIImageQuality {
  OpenAIImageQualityStandard
  OpenAIImageQualityHd
  OpenAIImageQualityLow
  OpenAIImageQualityMedium
  OpenAIImageQualityHigh
  OpenAIImageQualityXHigh
  OpenAIImageQualityMax
  OpenAIImageQualityAuto
}

///|
fn OpenAIImageQuality::wire_name(self : OpenAIImageQuality) -> String {
  match self {
    OpenAIImageQualityStandard => "standard"
    OpenAIImageQualityHd => "hd"
    OpenAIImageQualityLow => "low"
    OpenAIImageQualityMedium => "medium"
    OpenAIImageQualityHigh => "high"
    // 'xhigh' and 'max' are GPT Image 2.5 quality tiers.
    OpenAIImageQualityXHigh => "xhigh"
    OpenAIImageQualityMax => "max"
    OpenAIImageQualityAuto => "auto"
  }
}

///|
/// Background behavior for OpenAI image generation.
#derive(Debug, Eq)
pub(all) enum OpenAIImageBackground {
  OpenAIImageBackgroundTransparent
  OpenAIImageBackgroundOpaque
  OpenAIImageBackgroundAuto
}

///|
fn OpenAIImageBackground::wire_name(self : OpenAIImageBackground) -> String {
  match self {
    OpenAIImageBackgroundTransparent => "transparent"
    OpenAIImageBackgroundOpaque => "opaque"
    OpenAIImageBackgroundAuto => "auto"
  }
}

///|
/// Output format for OpenAI image generation.
#derive(Debug, Eq)
pub(all) enum OpenAIImageOutputFormat {
  OpenAIImageOutputPng
  OpenAIImageOutputJpeg
  OpenAIImageOutputWebp
}

///|
fn OpenAIImageOutputFormat::wire_name(self : OpenAIImageOutputFormat) -> String {
  match self {
    OpenAIImageOutputPng => "png"
    OpenAIImageOutputJpeg => "jpeg"
    OpenAIImageOutputWebp => "webp"
  }
}

///|
/// Style for OpenAI image generation.
#derive(Debug, Eq)
pub(all) enum OpenAIImageStyle {
  OpenAIImageStyleVivid
  OpenAIImageStyleNatural
}

///|
fn OpenAIImageStyle::wire_name(self : OpenAIImageStyle) -> String {
  match self {
    OpenAIImageStyleVivid => "vivid"
    OpenAIImageStyleNatural => "natural"
  }
}

///|
/// Content-moderation level for OpenAI image generation.
#derive(Debug, Eq)
pub(all) enum OpenAIImageModeration {
  OpenAIImageModerationAuto
  OpenAIImageModerationLow
}

///|
fn OpenAIImageModeration::wire_name(self : OpenAIImageModeration) -> String {
  match self {
    OpenAIImageModerationAuto => "auto"
    OpenAIImageModerationLow => "low"
  }
}

///|
/// Input fidelity for OpenAI image editing.
#derive(Debug, Eq)
pub(all) enum OpenAIImageInputFidelity {
  OpenAIImageInputFidelityHigh
  OpenAIImageInputFidelityLow
}

///|
fn OpenAIImageInputFidelity::wire_name(
  self : OpenAIImageInputFidelity,
) -> String {
  match self {
    OpenAIImageInputFidelityHigh => "high"
    OpenAIImageInputFidelityLow => "low"
  }
}

///|
fn validate_openai_image_compression(value : Int32?) -> Unit raise {
  if value is Some(number) && (number < 0 || number > 100) {
    fail("OpenAI image output_compression must be between 0 and 100")
  }
}

///|
fn openai_image_option_namespace(
  provider_name : String,
  quality : OpenAIImageQuality?,
  background : OpenAIImageBackground?,
  output_format : OpenAIImageOutputFormat?,
  output_compression : Int32?,
  user : String?,
  style : OpenAIImageStyle?,
  moderation : OpenAIImageModeration?,
  input_fidelity : OpenAIImageInputFidelity?,
) -> Map[String, Json] {
  openai_typed_namespace(
    provider_name,
    Map(
      [
        ..if quality is Some(value) {
          [("quality", Json::string(value.wire_name()))]
        },
        ..if background is Some(value) {
          [("background", Json::string(value.wire_name()))]
        },
        ..if output_format is Some(value) {
          [("outputFormat", Json::string(value.wire_name()))]
        },
        ..if output_compression is Some(value) {
          [("outputCompression", Json::number(value.to_double()))]
        },
        ..if user is Some(value) {
          [("user", Json::string(value))]
        },
        ..if style is Some(value) {
          [("style", Json::string(value.wire_name()))]
        },
        ..if moderation is Some(value) {
          [("moderation", Json::string(value.wire_name()))]
        },
        ..if input_fidelity is Some(value) {
          [("inputFidelity", Json::string(value.wire_name()))]
        },
      ],
    ),
  )
}

///|
/// Common typed provider options for OpenAI image models.
#derive(Debug, Eq)
pub(all) struct OpenAIImageModelOptions {
  quality : OpenAIImageQuality?
  background : OpenAIImageBackground?
  output_format : OpenAIImageOutputFormat?
  output_compression : Int32?
  user : String?
}

///|
/// Construct common OpenAI image options.
pub fn OpenAIImageModelOptions::new(
  quality? : OpenAIImageQuality,
  background? : OpenAIImageBackground,
  output_format? : OpenAIImageOutputFormat,
  output_compression? : Int32,
  user? : String,
) -> OpenAIImageModelOptions raise {
  validate_openai_image_compression(output_compression)
  { quality, background, output_format, output_compression, user, }
}

///|
/// Convert common image options to a provider-options namespace.
pub fn OpenAIImageModelOptions::to_provider_options(
  self : OpenAIImageModelOptions,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  openai_image_option_namespace(
    provider_name,
    self.quality,
    self.background,
    self.output_format,
    self.output_compression,
    self.user,
    None,
    None,
    None,
  )
}

///|
/// Typed provider options for OpenAI image generation requests.
#derive(Debug, Eq)
pub(all) struct OpenAIImageModelGenerationOptions {
  quality : OpenAIImageQuality?
  background : OpenAIImageBackground?
  output_format : OpenAIImageOutputFormat?
  output_compression : Int32?
  user : String?
  style : OpenAIImageStyle?
  moderation : OpenAIImageModeration?
}

///|
/// Construct typed OpenAI image-generation options.
pub fn OpenAIImageModelGenerationOptions::new(
  quality? : OpenAIImageQuality,
  background? : OpenAIImageBackground,
  output_format? : OpenAIImageOutputFormat,
  output_compression? : Int32,
  user? : String,
  style? : OpenAIImageStyle,
  moderation? : OpenAIImageModeration,
) -> OpenAIImageModelGenerationOptions raise {
  validate_openai_image_compression(output_compression)
  {
    quality,
    background,
    output_format,
    output_compression,
    user,
    style,
    moderation,
  }
}

///|
/// Convert typed image-generation options to a provider namespace.
pub fn OpenAIImageModelGenerationOptions::to_provider_options(
  self : OpenAIImageModelGenerationOptions,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  openai_image_option_namespace(
    provider_name,
    self.quality,
    self.background,
    self.output_format,
    self.output_compression,
    self.user,
    self.style,
    self.moderation,
    None,
  )
}

///|
/// Typed provider options for OpenAI image editing requests.
#derive(Debug, Eq)
pub(all) struct OpenAIImageModelEditOptions {
  quality : OpenAIImageQuality?
  background : OpenAIImageBackground?
  output_format : OpenAIImageOutputFormat?
  output_compression : Int32?
  user : String?
  input_fidelity : OpenAIImageInputFidelity?
}

///|
/// Construct typed OpenAI image-edit options.
pub fn OpenAIImageModelEditOptions::new(
  quality? : OpenAIImageQuality,
  background? : OpenAIImageBackground,
  output_format? : OpenAIImageOutputFormat,
  output_compression? : Int32,
  user? : String,
  input_fidelity? : OpenAIImageInputFidelity,
) -> OpenAIImageModelEditOptions raise {
  validate_openai_image_compression(output_compression)
  {
    quality,
    background,
    output_format,
    output_compression,
    user,
    input_fidelity,
  }
}

///|
/// Convert typed image-edit options to a provider namespace.
pub fn OpenAIImageModelEditOptions::to_provider_options(
  self : OpenAIImageModelEditOptions,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  openai_image_option_namespace(
    provider_name,
    self.quality,
    self.background,
    self.output_format,
    self.output_compression,
    self.user,
    None,
    None,
    self.input_fidelity,
  )
}

///|
/// Typed provider options for OpenAI speech synthesis models.
#derive(Debug, Eq)
pub(all) struct OpenAISpeechModelOptions {
  instructions : String?
  speed : Double?
}

///|
/// Construct typed OpenAI speech options.
pub fn OpenAISpeechModelOptions::new(
  instructions? : String,
  speed? : Double,
) -> OpenAISpeechModelOptions raise {
  if speed is Some(value) && (value < 0.25 || value > 4.0) {
    fail("OpenAI speech speed must be between 0.25 and 4.0")
  }
  { instructions, speed, }
}

///|
/// Convert typed speech options to a provider-options namespace.
pub fn OpenAISpeechModelOptions::to_provider_options(
  self : OpenAISpeechModelOptions,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  openai_typed_namespace(
    provider_name,
    Map(
      [
        ..if self.instructions is Some(value) {
          [("instructions", Json::string(value))]
        },
        ..if self.speed is Some(value) {
          [("speed", Json::number(value))]
        },
      ],
    ),
  )
}

///|
/// Timestamp granularity requested from OpenAI transcription models.
#derive(Debug, Eq)
pub(all) enum OpenAITranscriptionTimestampGranularity {
  OpenAITranscriptionWord
  OpenAITranscriptionSegment
}

///|
fn OpenAITranscriptionTimestampGranularity::wire_name(
  self : OpenAITranscriptionTimestampGranularity,
) -> String {
  match self {
    OpenAITranscriptionWord => "word"
    OpenAITranscriptionSegment => "segment"
  }
}

///|
/// Latency/accuracy tradeoff for realtime OpenAI transcription.
#derive(Debug, Eq)
pub(all) enum OpenAITranscriptionStreamingDelay {
  OpenAITranscriptionDelayMinimal
  OpenAITranscriptionDelayLow
  OpenAITranscriptionDelayMedium
  OpenAITranscriptionDelayHigh
  OpenAITranscriptionDelayXHigh
}

///|
fn OpenAITranscriptionStreamingDelay::wire_name(
  self : OpenAITranscriptionStreamingDelay,
) -> String {
  match self {
    OpenAITranscriptionDelayMinimal => "minimal"
    OpenAITranscriptionDelayLow => "low"
    OpenAITranscriptionDelayMedium => "medium"
    OpenAITranscriptionDelayHigh => "high"
    OpenAITranscriptionDelayXHigh => "xhigh"
  }
}

///|
/// Provider options specific to OpenAI realtime transcription.
#derive(Debug, Eq)
pub(all) struct OpenAITranscriptionStreamingOptions {
  delay : OpenAITranscriptionStreamingDelay?
  include_values : Array[String]?
}

///|
/// Construct typed realtime transcription options.
pub fn OpenAITranscriptionStreamingOptions::new(
  delay? : OpenAITranscriptionStreamingDelay,
  include_values? : Array[String],
) -> OpenAITranscriptionStreamingOptions {
  { delay, include_values, }
}

///|
fn OpenAITranscriptionStreamingOptions::to_json(
  self : OpenAITranscriptionStreamingOptions,
) -> Json {
  Json::object(
    Map(
      [
        ..if self.delay is Some(value) {
          [("delay", Json::string(value.wire_name()))]
        },
        ..if self.include_values is Some(values) {
          [
            (
              "include",
              Json::array([ for item in values => Json::string(item) ]),
            ),
          ]
        },
      ],
    ),
  )
}

///|
/// Typed provider options for OpenAI transcription models.
#derive(Debug, Eq)
pub(all) struct OpenAITranscriptionModelOptions {
  include_values : Array[String]?
  language : String?
  prompt : String?
  temperature : Double?
  timestamp_granularities : Array[OpenAITranscriptionTimestampGranularity]?
  streaming : OpenAITranscriptionStreamingOptions?
}

///|
/// Construct typed OpenAI transcription options.
pub fn OpenAITranscriptionModelOptions::new(
  include_values? : Array[String],
  language? : String,
  prompt? : String,
  temperature? : Double,
  timestamp_granularities? : Array[OpenAITranscriptionTimestampGranularity],
  streaming? : OpenAITranscriptionStreamingOptions,
) -> OpenAITranscriptionModelOptions raise {
  if temperature is Some(value) && (value < 0.0 || value > 1.0) {
    fail("OpenAI transcription temperature must be between 0 and 1")
  }
  {
    include_values,
    language,
    prompt,
    temperature,
    timestamp_granularities,
    streaming,
  }
}

///|
/// Convert typed transcription options to a provider-options namespace.
pub fn OpenAITranscriptionModelOptions::to_provider_options(
  self : OpenAITranscriptionModelOptions,
  provider_name~ : String = "openai",
) -> Map[String, Json] {
  openai_typed_namespace(
    provider_name,
    Map(
      [
        ..if self.include_values is Some(values) {
          [
            (
              "include",
              Json::array([ for item in values => Json::string(item) ]),
            ),
          ]
        },
        ..if self.language is Some(value) {
          [("language", Json::string(value))]
        },
        ..if self.prompt is Some(value) {
          [("prompt", Json::string(value))]
        },
        ..if self.temperature is Some(value) {
          [("temperature", Json::number(value))]
        },
        ..if self.timestamp_granularities is Some(values) {
          [
            (
              "timestampGranularities",
              Json::array(
                [
                  for value in values => Json::string(value.wire_name())
                ],
              ),
            ),
          ]
        },
        ..if self.streaming is Some(value) {
          [("streaming", value.to_json())]
        },
      ],
    ),
  )
}

///|
pub extend OpenAILogprobs with Debug::{to_repr}

///|
pub extend OpenAILogprobs with Eq::{not_equal, equal}

///|
pub extend OpenAIPromptCacheMode with Debug::{to_repr}

///|
pub extend OpenAIPromptCacheMode with Eq::{not_equal, equal}

///|
pub extend OpenAIPromptCacheTtl with Debug::{to_repr}

///|
pub extend OpenAIPromptCacheTtl with Eq::{not_equal, equal}

///|
pub extend OpenAIPromptCacheOptions with Debug::{to_repr}

///|
pub extend OpenAIPromptCacheOptions with Eq::{not_equal, equal}

///|
pub extend OpenAIServiceTier with Debug::{to_repr}

///|
pub extend OpenAIServiceTier with Eq::{not_equal, equal}

///|
pub extend OpenAIReasoningMode with Debug::{to_repr}

///|
pub extend OpenAIReasoningMode with Eq::{not_equal, equal}

///|
pub extend OpenAIReasoningContext with Debug::{to_repr}

///|
pub extend OpenAIReasoningContext with Eq::{not_equal, equal}

///|
pub extend OpenAITextVerbosity with Debug::{to_repr}

///|
pub extend OpenAITextVerbosity with Eq::{not_equal, equal}

///|
pub extend OpenAIPromptCacheRetention with Debug::{to_repr}

///|
pub extend OpenAIPromptCacheRetention with Eq::{not_equal, equal}

///|
pub extend OpenAISystemMessageMode with Debug::{to_repr}

///|
pub extend OpenAISystemMessageMode with Eq::{not_equal, equal}

///|
pub extend OpenAITruncation with Debug::{to_repr}

///|
pub extend OpenAITruncation with Eq::{not_equal, equal}

///|
pub extend OpenAIContextManagement with Debug::{to_repr}

///|
pub extend OpenAIContextManagement with Eq::{not_equal, equal}

///|
pub extend OpenAIAllowedToolsMode with Debug::{to_repr}

///|
pub extend OpenAIAllowedToolsMode with Eq::{not_equal, equal}

///|
pub extend OpenAIAllowedTools with Debug::{to_repr}

///|
pub extend OpenAIAllowedTools with Eq::{not_equal, equal}

///|
pub extend OpenAIResponsesInclude with Debug::{to_repr}

///|
pub extend OpenAIResponsesInclude with Eq::{not_equal, equal}

///|
pub extend OpenAILanguageModelResponsesOptions with Debug::{to_repr}

///|
pub extend OpenAILanguageModelChatOptions with Debug::{to_repr}

///|
pub extend OpenAILanguageModelCompletionOptions with Debug::{to_repr}

///|
pub extend OpenAIEmbeddingModelOptions with Debug::{to_repr}

///|
pub extend OpenAIEmbeddingModelOptions with Eq::{not_equal, equal}

///|
pub extend OpenAIImageQuality with Debug::{to_repr}

///|
pub extend OpenAIImageQuality with Eq::{not_equal, equal}

///|
pub extend OpenAIImageBackground with Debug::{to_repr}

///|
pub extend OpenAIImageBackground with Eq::{not_equal, equal}

///|
pub extend OpenAIImageOutputFormat with Debug::{to_repr}

///|
pub extend OpenAIImageOutputFormat with Eq::{not_equal, equal}

///|
pub extend OpenAIImageStyle with Debug::{to_repr}

///|
pub extend OpenAIImageStyle with Eq::{not_equal, equal}

///|
pub extend OpenAIImageModeration with Debug::{to_repr}

///|
pub extend OpenAIImageModeration with Eq::{not_equal, equal}

///|
pub extend OpenAIImageInputFidelity with Debug::{to_repr}

///|
pub extend OpenAIImageInputFidelity with Eq::{not_equal, equal}

///|
pub extend OpenAIImageModelOptions with Debug::{to_repr}

///|
pub extend OpenAIImageModelOptions with Eq::{not_equal, equal}

///|
pub extend OpenAIImageModelGenerationOptions with Debug::{to_repr}

///|
pub extend OpenAIImageModelGenerationOptions with Eq::{not_equal, equal}

///|
pub extend OpenAIImageModelEditOptions with Debug::{to_repr}

///|
pub extend OpenAIImageModelEditOptions with Eq::{not_equal, equal}

///|
pub extend OpenAISpeechModelOptions with Debug::{to_repr}

///|
pub extend OpenAISpeechModelOptions with Eq::{not_equal, equal}

///|
pub extend OpenAITranscriptionTimestampGranularity with Debug::{to_repr}

///|
pub extend OpenAITranscriptionTimestampGranularity with Eq::{not_equal, equal}

///|
pub extend OpenAITranscriptionStreamingDelay with Debug::{to_repr}

///|
pub extend OpenAITranscriptionStreamingDelay with Eq::{not_equal, equal}

///|
pub extend OpenAITranscriptionStreamingOptions with Debug::{to_repr}

///|
pub extend OpenAITranscriptionStreamingOptions with Eq::{not_equal, equal}

///|
pub extend OpenAITranscriptionModelOptions with Debug::{to_repr}

///|
pub extend OpenAITranscriptionModelOptions with Eq::{not_equal, equal}
