///|
fn paint_extension() -> OpenResponsesExtension {
  {
    id: "acme.paint",
    tool_type: Some("acme:canvas"),
    item_types: Some(["acme:stroke"]),
    event_types: Some(["acme:stroke.delta"]),
    encode_tool: Some((name, args) => {
      let fields : Map[String, Json] = Map([("tool", Json::string("canvas"))])
      fields["label"] = Json::string(name)
      match args {
        { "color": String(color), .. } => fields["color"] = Json::string(color)
        _ => ()
      }
      Some(Json::object(fields))
    }),
    encode_tool_choice: None,
    decode_item: Some((item, _mode) => {
      match item {
        { "color": String(color), .. } =>
          Some([@provider.LanguageModelV4Content::text("stroke: \{color}")])
        _ => None
      }
    }),
    encode_input_item: None,
    decode_event: Some((event, state) => {
      match event {
        { "delta": String(delta), .. } => {
          let count = match state.get("deltas") {
            Some(Number(value, ..)) => value.to_int()
            _ => 0
          }
          state["deltas"] = Json::number((count + 1).to_double())
          Some([
            @provider.TextDelta(id="stroke-0", delta~),
            @provider.CustomContentReady({
              kind: "acme.paint.progress",
              provider_metadata: Map([
                ("acme", { "deltas": Json::number((count + 1).to_double()) }),
              ]),
            }),
          ])
        }
        _ => None
      }
    }),
  }
}

///|
test "extension registry validates pairs and namespaces" {
  // Missing decode_item with item_types fails.
  let outcome = try {
    let _ = create_open_responses_extension_registry(extensions=[
      {
        id: "acme.paint",
        tool_type: None,
        item_types: Some(["acme:stroke"]),
        event_types: None,
        encode_tool: None,
        encode_tool_choice: None,
        decode_item: None,
        encode_input_item: None,
        decode_event: None,
      },
    ])
    None
  } catch {
    _ => Some(())
  }
  assert_true(outcome is Some(_))
  // Event types must share the extension id namespace.
  let outcome2 = try {
    let _ = create_open_responses_extension_registry(extensions=[
      {
        id: "acme.paint",
        tool_type: None,
        item_types: None,
        event_types: Some(["other:stroke"]),
        encode_tool: None,
        encode_tool_choice: None,
        decode_item: None,
        encode_input_item: None,
        decode_event: Some((_, _) => None),
      },
    ])
    None
  } catch {
    _ => Some(())
  }
  assert_true(outcome2 is Some(_))
  // A well-formed registry resolves lookups.
  let registry = create_open_responses_extension_registry(extensions=[
    paint_extension(),
  ])
  assert_true(registry.provider_tool_extension("acme.paint") is Some(_))
  assert_true(registry.item_extension("acme:stroke") is Some(_))
  assert_true(registry.event_extension("acme:stroke.delta") is Some(_))
}

///|
test "stream decoder routes namespaced extension events" {
  let registry = create_open_responses_extension_registry(extensions=[
    paint_extension(),
  ])
  let decoder = OpenResponsesStreamDecoder::new(extensions=registry)
  decoder.feed_line(
    "data: {\"type\":\"acme:stroke.delta\",\"sequence_number\":1,\"delta\":\"drip\"}",
  )
  |> ignore
  let batch = decoder.feed_line("")
  let events = batch.events
  assert_eq(events.length(), 2)
  match events[0] {
    @provider.TextDelta(id~, delta~) => {
      assert_eq(id, "stroke-0")
      assert_eq(delta, "drip")
    }
    _ => fail("expected text delta")
  }
  match events[1] {
    @provider.CustomContentReady(value) =>
      assert_eq(value.kind, "acme.paint.progress")
    _ => fail("expected custom content")
  }
  // State persists across events of the same stream.
  decoder.feed_line(
    "data: {\"type\":\"acme:stroke.delta\",\"sequence_number\":2,\"delta\":\"drop\"}",
  )
  |> ignore
  let batch2 = decoder.feed_line("")
  match batch2.events[1] {
    @provider.CustomContentReady(value) => {
      let metadata = value.provider_metadata.get("acme").unwrap()
      assert_eq(metadata.stringify(), "{\"deltas\":2}")
    }
    _ => fail("expected custom content")
  }
}
