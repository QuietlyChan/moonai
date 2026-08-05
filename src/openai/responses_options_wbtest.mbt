///|
test "OpenAI computer calls round-trip through Responses input" {
  let decoded = decode_openai_responses_response({
    "id": "resp-computer",
    "status": "completed",
    "output": [
      {
        "type": "computer_call",
        "id": "computer-item-1",
        "call_id": "computer-call-1",
        "status": "completed",
        "actions": [
          { "type": "scroll", "x": 10, "y": 20, "scroll_x": 0, "scroll_y": 500 },
        ],
        "pending_safety_checks": [
          { "id": "safety-1", "code": "confirm_action" },
        ],
      },
    ],
  })
  let call = match decoded.content[0] {
    @provider.GeneratedToolCallOutput(value) => value
    _ => fail("expected a computer tool call")
  }
  let output : Json = {
    "output": {
      "type": "computer_screenshot",
      "imageUrl": "https://example.com/screenshot.png",
      "fileId": "file-1",
      "detail": "high",
    },
    "acknowledgedSafetyChecks": [{ "id": "safety-1", "code": "confirm_action" }],
  }
  let warnings : Array[@provider.Warning] = []
  let input = convert_to_openai_responses_input(
    [
      @provider.LanguageModelMessage::assistant("", tool_calls=[call]),
      @provider.LanguageModelMessage::tool(call.id, output.stringify()),
    ],
    "system",
    false,
    "openai.responses",
    false,
    false,
    false,
    warnings,
    @provider_utils.ToolNameMapping::identity(),
  )
  assert_eq(warnings, [])
  json_inspect(Json::array(input), content=[
    {
      "type": "computer_call",
      "call_id": "computer-call-1",
      "id": "computer-item-1",
      "status": "completed",
      "actions": [
        { "type": "scroll", "x": 10, "y": 20, "scroll_x": 0, "scroll_y": 500 },
      ],
      "pending_safety_checks": [{ "id": "safety-1", "code": "confirm_action" }],
    },
    {
      "type": "computer_call_output",
      "call_id": "computer-call-1",
      "output": {
        "type": "computer_screenshot",
        "image_url": "https://example.com/screenshot.png",
        "file_id": "file-1",
        "detail": "high",
      },
      "acknowledged_safety_checks": [
        { "id": "safety-1", "code": "confirm_action" },
      ],
    },
  ])
}

///|
test "official OpenAI Responses reports capability warnings" {
  let prepared = prepare_openai_responses_request(
    "o1",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      temperature=0.7,
      top_p=0.9,
      top_k=40.0,
      provider_options={ "openai": { "serviceTier": "flex" } },
    ),
    "openai.responses",
    false,
  )
  assert_eq(prepared.warnings.length(), 4)
  assert_true(prepared.warnings[0] is @provider.Unsupported(feature="topK", ..))
  assert_true(
    prepared.warnings[1] is @provider.Unsupported(feature="temperature", ..),
  )
  assert_true(prepared.warnings[2] is @provider.Unsupported(feature="topP", ..))
  assert_true(
    prepared.warnings[3] is @provider.Unsupported(feature="serviceTier", ..),
  )
}

///|
test "official OpenAI ignores unrelated provider namespaces" {
  let prepared = prepare_openai_responses_request(
    "gpt-4o",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      provider_options={ "anthropic": { "thinking": { "type": "adaptive" } } },
    ),
    "openai.responses",
    false,
  )
  assert_eq(prepared.warnings, [])
  assert_false(prepared.body.stringify().contains("anthropic"))
  assert_false(prepared.body.stringify().contains("thinking"))
}

///|
test "official OpenAI Chat reports removed reasoning settings" {
  let prepared = prepare_openai_chat_request(
    "o1",
    @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("hello")],
      temperature=0.7,
      top_p=0.9,
      top_k=40.0,
      frequency_penalty=0.2,
      presence_penalty=0.3,
    ),
    "openai.chat",
    false,
    false,
    true,
  )
  assert_eq(prepared.warnings.length(), 5)
  assert_true(prepared.warnings[0] is @provider.Unsupported(feature="topK", ..))
  assert_true(
    prepared.warnings[1] is @provider.Unsupported(feature="temperature", ..),
  )
  assert_true(prepared.warnings[2] is @provider.Unsupported(feature="topP", ..))
  assert_true(
    prepared.warnings[3]
    is @provider.Unsupported(feature="frequencyPenalty", ..),
  )
  assert_true(
    prepared.warnings[4] is @provider.Unsupported(feature="presencePenalty", ..),
  )
}
