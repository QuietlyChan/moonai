///|
fn paint_extension() -> @protocol.OpenResponsesExtension {
  let encode_tool : (String, Json) -> Json? = (name, args) => {
    let fields : Map[String, Json] = Map([("tool", Json::string("canvas"))])
    fields["label"] = Json::string(name)
    match args {
      { "color": String(color), .. } => fields["color"] = Json::string(color)
      _ => ()
    }
    Some(Json::object(fields))
  }
  let decode_item : (Json, String) -> Array[@provider.LanguageModelV4Content]? = (
    item,
    _mode,
  ) => {
    match item {
      { "color": String(color), .. } =>
        Some([@provider.LanguageModelV4Content::text("stroke: \{color}")])
      _ => None
    }
  }
  {
    id: "acme.paint",
    tool_type: Some("acme:canvas"),
    item_types: Some(["acme:stroke"]),
    event_types: None,
    encode_tool: Some(encode_tool),
    encode_tool_choice: None,
    decode_item: Some(decode_item),
    encode_input_item: None,
    decode_event: None,
  }
}

///|
test "extension provider tools encode into the namespaced wire type" {
  let registry = @protocol.create_open_responses_extension_registry(extensions=[
    paint_extension(),
  ])
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[@provider.V4PromptText(text="paint", provider_options=Map([]))],
        provider_options=Map([]),
      ),
    ]),
    tools=[
      @provider.V4ProviderTool({
        id: "acme.paint",
        name: "canvas",
        args: { "color": "red" },
      }),
    ],
    tool_choice=@provider.V4ToolChoiceTool("canvas"),
  )
  let prepared = prepare_open_responses_v4_request(
    "or-1",
    options,
    "open_responses",
    false,
    extensions=registry,
  )
  let body = prepared.body.stringify()
  assert_true(body.contains("\"type\":\"acme:canvas\""))
  assert_true(body.contains("\"tool\":\"canvas\""))
  assert_true(body.contains("\"color\":\"red\""))
  assert_true(body.contains("\"tool_choice\":{\"type\":\"acme:canvas\"}"))
  assert_eq(prepared.warnings, [])
}

///|
test "generate responses decode extension items with a replay carrier" {
  let registry = @protocol.create_open_responses_extension_registry(extensions=[
    paint_extension(),
  ])
  let payload : Json = {
    "status": "completed",
    "output": [
      {
        "type": "acme:stroke",
        "id": "stroke_1",
        "status": "completed",
        "color": "red",
      },
    ],
  }
  let decoded = decode_open_responses_response_data(
    payload,
    id_generator=@provider_utils.generate_id,
    extensions=registry,
    provider_options_name="open_responses",
  )
  assert_eq(decoded.content.length(), 2)
  match decoded.content[0] {
    @provider.V4CustomOutput(value) => {
      assert_eq(value.kind, "open-responses.extension-replay")
      let metadata = value.provider_metadata.get("open_responses").unwrap()
      assert_true(metadata.stringify().contains("\"id\":\"acme.paint\""))
    }
    _ => fail("expected replay carrier")
  }
  match decoded.content[1] {
    @provider.V4TextOutput(value) => assert_eq(value.text, "stroke: red")
    _ => fail("expected decoded text")
  }
}
