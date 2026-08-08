///|
/// Small deterministic V4 model used to run every example without a key.
priv struct DemoLanguageModel {
  call_count : Ref[Int]
  selected_tool : Ref[String]
}

///|
fn DemoLanguageModel::new() -> DemoLanguageModel {
  { call_count: Ref(0), selected_tool: Ref("") }
}

///|
fn demo_last_user_text(prompt : @provider.LanguageModelV4Prompt) -> String {
  let mut result = ""
  for message in prompt.messages {
    match message {
      @provider.V4UserMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptText(text~, ..) => result = text
            _ => ()
          }
        }
      _ => ()
    }
  }
  result
}

///|
fn demo_last_tool_output(prompt : @provider.LanguageModelV4Prompt) -> Json? {
  let mut output : Json? = None
  for message in prompt.messages {
    match message {
      @provider.V4ToolMessage(content~, ..) =>
        for part in content {
          match part {
            @provider.V4PromptToolResult(result) =>
              match result.output {
                @provider.V4ToolResultJsonOutput(value~, ..) =>
                  output = Some(value)
                @provider.V4ToolResultTextOutput(value~, ..) =>
                  output = Some(Json::string(value))
                @provider.V4ToolResultErrorJson(value~, ..) =>
                  output = Some(value)
                @provider.V4ToolResultErrorText(value~, ..) =>
                  output = Some({ "error": value })
                @provider.V4ToolResultExecutionDenied(reason~, ..) =>
                  output = Some({
                    "error": reason.unwrap_or("tool execution denied"),
                  })
                @provider.V4ToolResultContentOutput(..) => ()
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  output
}

///|
fn demo_tool_call(user_text : String) -> (String, String) {
  let normalized = user_text.to_lower()
  if normalized.contains("weather") || normalized.contains("forecast") {
    ("get_weather", ({ "city": "Hangzhou" } : Json).stringify())
  } else if normalized.contains("calculate") || normalized.contains("*") {
    (
      "calculator",
      ({ "operation": "multiply", "a": 42, "b": 8 } : Json).stringify(),
    )
  } else {
    (
      "search_moonai",
      ({ "query": if user_text == "" { "MoonAI" } else { user_text } } : Json).stringify(),
    )
  }
}

///|
fn demo_usage(
  input_tokens : Int,
  output_tokens : Int,
) -> @provider.LanguageModelV4Usage {
  @provider.LanguageModelV4Usage::from_usage(
    @provider.Usage::new(input_tokens~, output_tokens~),
  )
}

///|
fn demo_finish_reason(
  reason : @provider.LanguageModelV4UnifiedFinishReason,
) -> @provider.LanguageModelV4FinishReason {
  { unified: reason, raw: Some("demo") }
}

///|
fn DemoLanguageModel::next_output(
  self : DemoLanguageModel,
  options : @provider.LanguageModelV4CallOptions,
) -> (
  Array[@provider.LanguageModelV4Content],
  @provider.LanguageModelV4FinishReason,
) {
  let index = self.call_count.val
  self.call_count.val = index + 1
  if options.tools.length() > 0 && index == 0 {
    let (tool_name, input) = demo_tool_call(demo_last_user_text(options.prompt))
    self.selected_tool.val = tool_name
    (
      [
        @provider.LanguageModelV4Content::tool_call({
          tool_call_id: "demo-call-1",
          tool_name,
          input,
          provider_executed: false,
          dynamic: false,
          provider_metadata: Map([]),
        }),
      ],
      demo_finish_reason(@provider.V4FinishToolCalls),
    )
  } else {
    let text = match demo_last_tool_output(options.prompt) {
      Some(value) =>
        "The " +
        self.selected_tool.val +
        " tool returned " +
        value.stringify() +
        ". This response was composed by MoonAI's multi-step agent loop."
      None =>
        "MoonAI is a provider-neutral MoonBit SDK for streaming text, structured provider options, and tool-driven agents. Set MOONAI_PROVIDER to connect this example to a live model."
    }
    (
      [@provider.LanguageModelV4Content::text(text)],
      demo_finish_reason(@provider.V4FinishStop),
    )
  }
}

///|
impl @provider.LanguageModelV4 for DemoLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.LanguageModelV4 for DemoLanguageModel with fn provider(_self) -> String {
  "moonai.demo"
}

///|
impl @provider.LanguageModelV4 for DemoLanguageModel with fn model_id(_self) -> String {
  "moonai-demo"
}

///|
impl @provider.LanguageModelV4 for DemoLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
impl @provider.LanguageModelV4 for DemoLanguageModel with fn do_generate(
  self,
  options,
) {
  let (content, finish_reason) = self.next_output(options)
  {
    content,
    finish_reason,
    usage: demo_usage(12, 20),
    provider_metadata: Map([("demo", { "deterministic": true })]),
    request: None,
    response: None,
    warnings: [],
  }
}

///|
impl @provider.LanguageModelV4 for DemoLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  let (content, finish_reason) = self.next_output(options)
  on_event(@provider.V4StreamStart(warnings=[]))
  for part in content {
    match part {
      @provider.V4ToolCallOutput(call) => {
        on_event(
          @provider.V4ToolInputStart(
            id=call.tool_call_id,
            tool_name=call.tool_name,
            provider_executed=false,
            dynamic=false,
            title=None,
            provider_metadata=Map([]),
          ),
        )
        on_event(
          @provider.V4ToolInputDelta(
            id=call.tool_call_id,
            delta=call.input,
            provider_metadata=Map([]),
          ),
        )
        on_event(
          @provider.V4ToolInputEnd(
            id=call.tool_call_id,
            provider_metadata=Map([]),
          ),
        )
        on_event(@provider.V4ToolCallReady(call))
      }
      @provider.V4TextOutput(text) => {
        on_event(
          @provider.V4TextStart(id="demo-text-1", provider_metadata=Map([])),
        )
        on_event(
          @provider.V4TextDelta(
            id="demo-text-1",
            delta=text.text,
            provider_metadata=Map([]),
          ),
        )
        on_event(
          @provider.V4TextEnd(id="demo-text-1", provider_metadata=Map([])),
        )
      }
      _ => ()
    }
  }
  on_event(
    @provider.V4Finish(
      usage=demo_usage(12, 20),
      reason=finish_reason,
      provider_metadata=Map([("demo", { "deterministic": true })]),
    ),
  )
  @provider.LanguageModelV4StreamResult::new(None, None)
}
