///|
priv struct OpenAIResponsesOptions {
  conversation : String?
  include_values : Array[String]
  instructions : String?
  top_logprobs : Int?
  max_tool_calls : Int?
  metadata : Json?
  parallel_tool_calls : Bool?
  previous_response_id : String?
  prompt_cache_key : String?
  prompt_cache_options : Json?
  prompt_cache_retention : String?
  reasoning_effort : String?
  reasoning_mode : String?
  reasoning_context : String?
  reasoning_summary : String?
  safety_identifier : String?
  service_tier : String?
  store : Bool?
  pass_through_unsupported_files : Bool
  strict_json_schema : Bool
  text_verbosity : String?
  truncation : String?
  user : String?
  system_message_mode : String?
  force_reasoning : Bool?
  context_management : Array[Json]
  allowed_tools : Json?
}

///|
priv struct ParsedOpenAIResponsesOptions {
  options : OpenAIResponsesOptions
  warnings : Array[@provider.Warning]
}

///|
priv struct OpenAIPreparedResponsesRequest {
  body : Json
  warnings : Array[@provider.Warning]
  tool_name_mapping : @provider_utils.ToolNameMapping
}

///|
fn openai_responses_reserved_fields() -> Array[String] {
  [
    "model", "input", "stream", "temperature", "top_p", "max_output_tokens", "text",
    "reasoning", "tools", "tool_choice",
  ]
}

///|
fn parse_openai_include(
  reader : @provider_utils.ProviderOptionsReader,
) -> Array[String] {
  let result : Array[String] = []
  guard reader.take_array("include") is Some(values) else { return result }
  let allowed = [
    "reasoning.encrypted_content", "file_search_call.results", "web_search_call.results",
    "web_search_call.action.sources", "code_interpreter_call.outputs", "computer_call_output.output.image_url",
    "message.input_image.image_url", "message.output_text.logprobs",
  ]
  for value in values {
    match value {
      String(item) if allowed.any(candidate => candidate == item) =>
        result.push(item)
      _ =>
        reader.add_warning(
          @provider.Warning::Compatibility(
            feature="providerOptions.include",
            details="Unsupported include entry was ignored.",
          ),
        )
    }
  }
  result
}

///|
fn parse_openai_logprobs(
  reader : @provider_utils.ProviderOptionsReader,
) -> Int? {
  match reader.take_json("logprobs") {
    Some(True) => Some(20)
    Some(False) => None
    Some(Number(value, ..)) => {
      let top = value.to_int()
      if top >= 1 && top <= 20 {
        Some(top)
      } else {
        reader.add_warning(
          @provider.Warning::Compatibility(
            feature="providerOptions.logprobs",
            details="Expected true, false, or an integer from 1 through 20; the invalid value was ignored.",
          ),
        )
        None
      }
    }
    Some(_) => {
      reader.add_warning(
        @provider.Warning::Compatibility(
          feature="providerOptions.logprobs",
          details="Expected a boolean or integer; the invalid value was ignored.",
        ),
      )
      None
    }
    None => None
  }
}

///|
fn parse_openai_responses_options(
  options : @provider.ChatCallOptions,
  provider_name : String,
) -> ParsedOpenAIResponsesOptions {
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name~,
    aliases=["openai"],
    reserved_fields=openai_responses_reserved_fields(),
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let conversation = reader.take_string("conversation")
  let include_values = parse_openai_include(reader)
  let instructions = reader.take_string("instructions")
  let top_logprobs = parse_openai_logprobs(reader)
  let max_tool_calls = reader.take_int(
    "maxToolCalls",
    aliases=["max_tool_calls"],
    min=0,
  )
  let metadata = reader.take_json("metadata")
  let parallel_tool_calls = reader.take_bool("parallelToolCalls", aliases=[
    "parallel_tool_calls",
  ])
  let previous_response_id = reader.take_string("previousResponseId", aliases=[
    "previous_response_id",
  ])
  let prompt_cache_key = reader.take_string("promptCacheKey", aliases=[
    "prompt_cache_key",
  ])
  let prompt_cache_options = reader.take_json("promptCacheOptions", aliases=[
    "prompt_cache_options",
  ])
  let prompt_cache_retention = reader.take_string(
    "promptCacheRetention",
    aliases=["prompt_cache_retention"],
    allowed=["in_memory", "24h"],
  )
  let reasoning_effort = reader.take_string("reasoningEffort", aliases=[
    "reasoning_effort",
  ])
  let reasoning_mode = reader.take_string(
    "reasoningMode",
    aliases=["reasoning_mode"],
    allowed=["standard", "pro"],
  )
  let reasoning_context = reader.take_string(
    "reasoningContext",
    aliases=["reasoning_context"],
    allowed=["auto", "current_turn", "all_turns"],
  )
  let reasoning_summary = reader.take_string("reasoningSummary", aliases=[
    "reasoning_summary",
  ])
  let safety_identifier = reader.take_string("safetyIdentifier", aliases=[
    "safety_identifier",
  ])
  let service_tier = reader.take_string(
    "serviceTier",
    aliases=["service_tier"],
    allowed=["auto", "flex", "priority", "default"],
  )
  let store = reader.take_bool("store")
  let pass_through_unsupported_files = reader
    .take_bool("passThroughUnsupportedFiles", aliases=[
      "pass_through_unsupported_files",
    ])
    .unwrap_or(false)
  let strict_json_schema = reader
    .take_bool("strictJsonSchema", aliases=["strict_json_schema"])
    .unwrap_or(true)
  let text_verbosity = reader.take_string(
    "textVerbosity",
    aliases=["text_verbosity"],
    allowed=["low", "medium", "high"],
  )
  let truncation = reader.take_string("truncation", allowed=["auto", "disabled"])
  let user = reader.take_string("user")
  let system_message_mode = reader.take_string(
    "systemMessageMode",
    aliases=["system_message_mode"],
    allowed=["system", "developer", "remove"],
  )
  let force_reasoning = reader.take_bool("forceReasoning", aliases=[
    "force_reasoning",
  ])
  let context_management = reader
    .take_array("contextManagement", aliases=["context_management"])
    .unwrap_or([])
  let allowed_tools = reader.take_json("allowedTools", aliases=["allowed_tools"])
  {
    options: {
      conversation,
      include_values,
      instructions,
      top_logprobs,
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
    },
    warnings: reader.diagnostics(),
  }
}

///|
fn openai_reasoning_effort(effort : @provider.ReasoningEffort) -> String? {
  match effort {
    @provider.ProviderDefault => None
    @provider.Disabled => Some("none")
    @provider.Minimal => Some("minimal")
    @provider.Low => Some("low")
    @provider.Medium => Some("medium")
    @provider.High => Some("high")
    @provider.XHigh => Some("xhigh")
  }
}

///|
priv struct OpenAIChatOptions {
  logit_bias : Json?
  logprobs : Bool
  top_logprobs : Int?
  parallel_tool_calls : Bool?
  user : String?
  reasoning_effort : String?
  max_completion_tokens : Int?
  store : Bool?
  metadata : Json?
  prediction : Json?
  service_tier : String?
  strict_json_schema : Bool
  text_verbosity : String?
  prompt_cache_key : String?
  prompt_cache_options : Json?
  prompt_cache_retention : String?
  safety_identifier : String?
  system_message_mode : String?
  force_reasoning : Bool?
}

///|
priv struct ParsedOpenAIChatOptions {
  options : OpenAIChatOptions
  warnings : Array[@provider.Warning]
}

///|
priv struct OpenAIPreparedChatRequest {
  body : Json
  warnings : Array[@provider.Warning]
}

///|
fn openai_chat_reserved_fields() -> Array[String] {
  [
    "model", "messages", "stream", "stream_options", "max_tokens", "temperature",
    "top_p", "frequency_penalty", "presence_penalty", "seed", "stop", "tools", "tool_choice",
    "response_format",
  ]
}

///|
fn parse_openai_chat_logprobs(
  reader : @provider_utils.ProviderOptionsReader,
) -> (Bool, Int?) {
  match reader.take_json("logprobs") {
    Some(True) => (true, Some(0))
    Some(False) => (false, None)
    Some(Number(value, ..)) => (true, Some(value.to_int()))
    Some(_) => {
      reader.add_warning(
        @provider.Warning::Compatibility(
          feature="providerOptions.logprobs",
          details="Expected a boolean or number; the invalid value was ignored.",
        ),
      )
      (false, None)
    }
    None => (false, None)
  }
}

///|
fn parse_openai_chat_options(
  options : @provider.ChatCallOptions,
  provider_name : String,
) -> ParsedOpenAIChatOptions {
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name~,
    aliases=["openai"],
    reserved_fields=openai_chat_reserved_fields(),
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let logit_bias = reader.take_json("logitBias", aliases=["logit_bias"])
  let (logprobs, top_logprobs) = parse_openai_chat_logprobs(reader)
  let parallel_tool_calls = reader.take_bool("parallelToolCalls", aliases=[
    "parallel_tool_calls",
  ])
  let user = reader.take_string("user")
  let reasoning_effort = reader.take_string(
    "reasoningEffort",
    aliases=["reasoning_effort"],
    allowed=["none", "minimal", "low", "medium", "high", "xhigh", "max"],
  )
  let max_completion_tokens = reader.take_int(
    "maxCompletionTokens",
    aliases=["max_completion_tokens"],
    min=1,
  )
  let store = reader.take_bool("store")
  let metadata = reader.take_json("metadata")
  let prediction = reader.take_json("prediction")
  let service_tier = reader.take_string(
    "serviceTier",
    aliases=["service_tier"],
    allowed=["auto", "flex", "priority", "default"],
  )
  let strict_json_schema = reader
    .take_bool("strictJsonSchema", aliases=["strict_json_schema"])
    .unwrap_or(true)
  let text_verbosity = reader.take_string(
    "textVerbosity",
    aliases=["text_verbosity"],
    allowed=["low", "medium", "high"],
  )
  let prompt_cache_key = reader.take_string("promptCacheKey", aliases=[
    "prompt_cache_key",
  ])
  let prompt_cache_options = reader.take_json("promptCacheOptions", aliases=[
    "prompt_cache_options",
  ])
  let prompt_cache_retention = reader.take_string(
    "promptCacheRetention",
    aliases=["prompt_cache_retention"],
    allowed=["in_memory", "24h"],
  )
  let safety_identifier = reader.take_string("safetyIdentifier", aliases=[
    "safety_identifier",
  ])
  let system_message_mode = reader.take_string(
    "systemMessageMode",
    aliases=["system_message_mode"],
    allowed=["system", "developer", "remove"],
  )
  let force_reasoning = reader.take_bool("forceReasoning", aliases=[
    "force_reasoning",
  ])
  {
    options: {
      logit_bias,
      logprobs,
      top_logprobs,
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
    },
    warnings: reader.diagnostics(),
  }
}

///|
priv struct OpenAIImageOptions {
  quality : String?
  style : String?
  background : String?
  moderation : String?
  output_format : String?
  output_compression : Int?
  input_fidelity : String?
  user : String?
}

///|
priv struct ParsedOpenAIImageOptions {
  options : OpenAIImageOptions
  warnings : Array[@provider.Warning]
}

///|
fn openai_image_reserved_fields() -> Array[String] {
  ["model", "prompt", "image", "mask", "n", "size", "response_format"]
}

///|
fn parse_openai_image_options(
  call_options : @provider.ImageCallOptions,
  provider_name : String,
) -> ParsedOpenAIImageOptions {
  let resolution = @provider_utils.resolve_provider_options(
    call_options.provider_options,
    provider_name~,
    aliases=["openai"],
    reserved_fields=openai_image_reserved_fields(),
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  let quality = reader.take_string("quality", allowed=[
    "standard", "hd", "low", "medium", "high", "auto",
  ])
  let style = reader.take_string("style", allowed=["vivid", "natural"])
  let background = reader.take_string("background", allowed=[
    "transparent", "opaque", "auto",
  ])
  let moderation = reader.take_string("moderation", allowed=["auto", "low"])
  let output_format = reader.take_string(
    "outputFormat",
    aliases=["output_format"],
    allowed=["png", "jpeg", "webp"],
  )
  let output_compression = reader.take_int(
    "outputCompression",
    aliases=["output_compression"],
    min=0,
    max=100,
  )
  let input_fidelity = reader.take_string(
    "inputFidelity",
    aliases=["input_fidelity"],
    allowed=["high", "low"],
  )
  let user = reader.take_string("user")
  {
    options: {
      quality,
      style,
      background,
      moderation,
      output_format,
      output_compression,
      input_fidelity,
      user,
    },
    warnings: reader.diagnostics(),
  }
}

///|
priv struct OpenAIEmbeddingOptions {
  dimensions : Int?
  user : String?
}

///|
priv struct ParsedOpenAIEmbeddingOptions {
  options : OpenAIEmbeddingOptions
  warnings : Array[@provider.Warning]
}

///|
fn parse_openai_embedding_options(
  call_options : @provider.EmbeddingOptions,
  provider_name : String,
) -> ParsedOpenAIEmbeddingOptions {
  let resolution = @provider_utils.resolve_provider_options(
    call_options.provider_options,
    provider_name~,
    aliases=["openai"],
    reserved_fields=["model", "input", "encoding_format"],
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  {
    options: {
      dimensions: reader.take_int("dimensions", min=1),
      user: reader.take_string("user"),
    },
    warnings: reader.diagnostics(),
  }
}

///|
priv struct OpenAICompletionOptions {
  echo : Bool?
  logit_bias : Json?
  logprobs : Int?
  suffix : String?
  user : String?
}

///|
priv struct ParsedOpenAICompletionOptions {
  options : OpenAICompletionOptions
  warnings : Array[@provider.Warning]
}

///|
fn parse_openai_completion_logprobs(
  reader : @provider_utils.ProviderOptionsReader,
) -> Int? {
  match reader.take_json("logprobs") {
    Some(True) => Some(0)
    Some(False) => None
    Some(Number(value, ..)) =>
      match @provider_utils.json_number_as_int(value) {
        Some(result) if result >= 0 => Some(result)
        _ => {
          reader.add_warning(
            @provider.Warning::Compatibility(
              feature="providerOptions.logprobs",
              details="Expected a non-negative integer; the invalid value was ignored.",
            ),
          )
          None
        }
      }
    Some(_) => {
      reader.add_warning(
        @provider.Warning::Compatibility(
          feature="providerOptions.logprobs",
          details="Expected a boolean or integer; the invalid value was ignored.",
        ),
      )
      None
    }
    None => None
  }
}

///|
fn parse_openai_completion_options(
  call_options : @provider.CompletionOptions,
  provider_name : String,
) -> ParsedOpenAICompletionOptions {
  let resolution = @provider_utils.resolve_provider_options(
    call_options.provider_options,
    provider_name~,
    aliases=["openai"],
    reserved_fields=[
      "model", "prompt", "stream", "stream_options", "max_tokens", "temperature",
      "top_p", "frequency_penalty", "presence_penalty", "seed", "stop",
    ],
  )
  let reader = @provider_utils.ProviderOptionsReader::new(resolution)
  {
    options: {
      echo: reader.take_bool("echo"),
      logit_bias: reader.take_json("logitBias", aliases=["logit_bias"]),
      logprobs: parse_openai_completion_logprobs(reader),
      suffix: reader.take_string("suffix"),
      user: reader.take_string("user"),
    },
    warnings: reader.diagnostics(),
  }
}
