///|
struct PromptTestModel {}

///|
impl @provider.ChatModel for PromptTestModel with fn provider(_self) -> String {
  "prompt-test"
}

///|
impl @provider.ChatModel for PromptTestModel with fn model_id(_self) -> String {
  "prompt-test-model"
}

///|
impl @provider.ChatModel for PromptTestModel with fn supported_urls(_self) -> Array[
  @provider.SupportedUrlRule,
] {
  []
}

///|
impl @provider.ChatModel for PromptTestModel with fn generate(_self, _options) {
  @provider.ChatResponse::empty()
}

///|
impl @provider.ChatModel for PromptTestModel with fn stream(
  _self,
  _options,
  _on_event,
) {
  @provider.ChatResponse::empty()
}

///|
async test "prompt conversion rewrites URLs and preserves provider options" {
  let provider_options : Map[String, Json] = {
    "anthropic": { "cacheControl": { "type": "ephemeral" } },
  }
  let messages = [
    @provider_utils.ModelMessage::user_parts(
      [
        @provider_utils.ModelContentPart::image_url(
          "https://example.com/image.png",
        ).with_provider_options(provider_options),
      ],
      provider_options~,
    ),
  ]
  let captured_requests : Array[DownloadRequest] = []
  let download : DownloadFunction = requests => {
    for request in requests {
      captured_requests.push(request)
    }
    [
      Some(
        DownloadedAsset::new(data=@utf8.encode("PNG"), media_type="image/png"),
      ),
    ]
  }
  let converted = convert_to_language_model_prompt(
    standardize_prompt(None, messages),
    PromptTestModel::{  },
    Some(download),
    @provider.RetryPolicy::none(),
    None,
  )
  assert_eq(captured_requests, [
    DownloadRequest::new(
      url="https://example.com/image.png",
      is_url_supported_by_model=false,
    ),
  ])
  assert_true(converted[0].provider_options.get("anthropic") is Some(_))
  assert_eq(
    converted[0].parts[0].without_provider_options(),
    @provider.LanguageModelContentPart::image_data(
      data="UE5H",
      media_type="image/png",
    ),
  )
  assert_true(
    converted[0].parts[0].provider_options().get("anthropic") is Some(_),
  )
}

///|
async test "prompt conversion serializes structured high-level tool input" {
  let messages = [
    @provider_utils.ModelMessage::assistant("", tool_calls=[
      @provider_utils.ModelToolCall::new(id="call-1", name="weather", input={
        "city": "Shanghai",
      }),
    ]),
  ]
  let converted = convert_to_language_model_prompt(
    standardize_prompt(None, messages),
    PromptTestModel::{  },
    None,
    @provider.RetryPolicy::none(),
    None,
  )
  assert_eq(converted.length(), 1)
  assert_eq(converted[0].tool_calls.length(), 1)
  assert_eq(converted[0].tool_calls[0].arguments, "{\"city\":\"Shanghai\"}")
}

///|
async test "prompt conversion maps tool results and approval responses" {
  let result = @provider_utils.ModelToolResult::json(
    tool_call_id="call-1",
    tool_name="weather",
    value={ "temperature": 18 },
  )
  let approval = @provider_utils.ModelToolApprovalResponse::new(
    approval_id="approval-1",
    approved=false,
    reason="not now",
    provider_executed=true,
  )
  let message = @provider_utils.ModelMessage::tool_content([
    @provider_utils.ModelContentPart::tool_result(result),
    @provider_utils.ModelContentPart::tool_approval_response(approval),
  ])
  let converted = convert_to_language_model_prompt(
    standardize_prompt(None, [message]),
    PromptTestModel::{  },
    None,
    @provider.RetryPolicy::none(),
    None,
  )
  assert_eq(converted.length(), 1)
  assert_true(converted[0].parts[0] is @provider.ToolResultPart(_))
  assert_true(converted[0].parts[1] is @provider.ToolApprovalResponsePart(_))
  match converted[0].parts[0].without_provider_options() {
    @provider.ToolResultPart(result) =>
      assert_true(result.output is @provider.LanguageModelToolJsonOutput(..))
    _ => fail("expected provider tool result part")
  }
}

///|
async test "prompt conversion downloads nested tool-result files" {
  let result = @provider_utils.ModelToolResult::{
    tool_call_id: "call-file",
    tool_name: "inspect",
    output: @provider_utils.ModelToolContent(
      value=[
        @provider_utils.ModelToolResultFileUrl(
          url="https://example.com/output.txt",
          media_type="text/plain",
          filename="output.txt",
          provider_options=Map([]),
        ),
      ],
      provider_options=Map([]),
    ),
    provider_options: Map([]),
  }
  let message = @provider_utils.ModelMessage::tool_content([
    @provider_utils.ModelContentPart::tool_result(result),
  ])
  let captured_requests : Array[DownloadRequest] = []
  let download : DownloadFunction = requests => {
    for request in requests {
      captured_requests.push(request)
    }
    [
      Some(
        DownloadedAsset::new(
          data=@utf8.encode("tool output"),
          media_type="text/plain",
        ),
      ),
    ]
  }
  let converted = convert_to_language_model_prompt(
    standardize_prompt(None, [message]),
    PromptTestModel::{  },
    Some(download),
    @provider.RetryPolicy::none(),
    None,
  )
  assert_eq(captured_requests, [
    DownloadRequest::new(
      url="https://example.com/output.txt",
      is_url_supported_by_model=false,
    ),
  ])
  match converted[0].parts[0].without_provider_options() {
    @provider.ToolResultPart(result) =>
      match result.output {
        @provider.LanguageModelToolContent(value~, ..) =>
          assert_true(value[0] is @provider.LanguageModelToolFileData(..))
        _ => fail("expected structured tool content")
      }
    _ => fail("expected tool result part")
  }
}
