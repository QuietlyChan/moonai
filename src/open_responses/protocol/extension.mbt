///|
/// Input parts an extension can encode back into wire items when no
/// original wire item is available (history replay).
pub(all) enum OpenResponsesExtensionInputPart {
  ToolCallPart(@provider.LanguageModelV4ToolCallPart)
  ToolResultPart(@provider.LanguageModelV4ToolResultPart)
}

///|
/// Defines how the provider encodes and decodes an Open Responses extension.
///
/// Tool, item, and event codecs can be registered independently. The
/// extension id uses `<implementor>.<extension>` format; wire types use
/// `<implementor>:<tool>` format.
///
/// Streaming extensions express item results through `decode_event`
/// (stream-equivalent events); `decode_item` handles completed items in
/// non-streaming responses, mirroring the upstream `mode` split.
pub(all) struct OpenResponsesExtension {
  /// Extension ID in `<implementor>.<extension>` format. For extensions
  /// that encode a provider tool, this is also the provider-tool ID.
  id : String
  /// Namespaced tool type; must be provided together with `encode_tool`.
  tool_type : String?
  /// Namespaced item types decoded by this extension; must be provided
  /// together with `decode_item`.
  item_types : Array[String]?
  /// Namespaced event types decoded by this extension; must be provided
  /// together with `decode_event`.
  event_types : Array[String]?
  /// Encodes a provider tool. Returns the wire fields (the adapter adds
  /// `type: tool_type`), or None when the arguments cannot be encoded.
  encode_tool : ((String, Json) -> Json?)?
  /// Encodes a specific tool choice. The adapter adds `type: tool_type`.
  encode_tool_choice : ((String, Json) -> Json?)?
  /// Decodes a completed namespaced item into content parts. The adapter
  /// prepends a custom replay carrier carrying the original item.
  decode_item : ((Json, String) -> Array[@provider.LanguageModelV4Content]?)?
  /// Encodes a history part when no original wire item is available.
  encode_input_item : ((
    OpenResponsesExtensionInputPart,
    @provider.LanguageModelV4ProviderTool,
  ) -> Json?)?
  /// Decodes a namespaced streaming event. `state` persists for the
  /// lifetime of one response stream.
  decode_event : ((Json, Map[String, Json]) -> Array[@provider.StreamEvent]?)?
}

///|
/// Return whether a wire type uses the `<implementor>:<tool>` namespace.
pub fn is_namespaced_open_responses_type(type_name : String) -> Bool {
  match type_name.find(":") {
    Some(index) => index > 0 && index < type_name.length() - 1
    None => false
  }
}

///|
fn open_responses_extension_namespace(extension_id : String) -> String? {
  match extension_id.find(".") {
    Some(index) if index > 0 => Some(extension_id[:index].to_owned())
    _ => None
  }
}

///|
fn assert_namespaced_open_responses_type(
  extension_id~ : String,
  namespace_prefix~ : String,
  type_name~ : String,
  field~ : String,
) -> Unit raise {
  guard is_namespaced_open_responses_type(type_name) else {
    fail(
      "Open Responses extension \{extension_id} \{field} must use <implementor>:<tool> format",
    )
  }
  match type_name.find(":") {
    Some(index) => {
      let prefix = type_name[:index].to_owned()
      guard prefix == namespace_prefix else {
        fail(
          "Open Responses extension \{extension_id} \{field} namespace must match the extension id",
        )
      }
    }
    None => fail("unreachable namespaced type check")
  }
}

///|
fn register_unique_extension(
  registry~ : OpenResponsesExtensionRegistry,
  extension~ : OpenResponsesExtension,
  key~ : String,
  field~ : String,
) -> Unit raise {
  let existing = match field {
    "id" => registry.by_extension_id.get(key)
    "provider-tool id" => registry.by_provider_tool_id.get(key)
    "toolType" => registry.by_tool_type.get(key)
    "itemTypes" => registry.by_item_type.get(key)
    "eventTypes" => registry.by_event_type.get(key)
    _ => None
  }
  guard existing is None else {
    fail(
      "Open Responses extension \{extension.id} \{field} \"\{key}\" is already registered",
    )
  }
  match field {
    "id" => registry.by_extension_id[key] = extension
    "provider-tool id" => registry.by_provider_tool_id[key] = extension
    "toolType" => registry.by_tool_type[key] = extension
    "itemTypes" => registry.by_item_type[key] = extension
    "eventTypes" => registry.by_event_type[key] = extension
    _ => ()
  }
}

///|
/// Registry resolving extensions by wire type, id, and provider-tool id.
pub struct OpenResponsesExtensionRegistry {
  priv by_event_type : Map[String, OpenResponsesExtension]
  priv by_extension_id : Map[String, OpenResponsesExtension]
  priv by_item_type : Map[String, OpenResponsesExtension]
  priv by_provider_tool_id : Map[String, OpenResponsesExtension]
  priv by_tool_type : Map[String, OpenResponsesExtension]
}

///|
/// Build a validated extension registry.
pub fn create_open_responses_extension_registry(
  extensions? : Array[OpenResponsesExtension] = [],
) -> OpenResponsesExtensionRegistry raise {
  let registry = {
    by_event_type: {},
    by_extension_id: {},
    by_item_type: {},
    by_provider_tool_id: {},
    by_tool_type: {},
  }
  for extension in extensions {
    let namespace_prefix = match
      open_responses_extension_namespace(extension.id) {
      Some(value) => value
      None =>
        fail(
          "Open Responses extension ID \{extension.id} must use <implementor>.<extension> format.",
        )
    }
    register_unique_extension(
      registry~,
      extension~,
      key=extension.id,
      field="id",
    )
    let has_tool_type = extension.tool_type is Some(_)
    let has_tool_encoder = extension.encode_tool is Some(_)
    guard has_tool_type == has_tool_encoder else {
      fail(
        "Open Responses extension \{extension.id} must provide tool_type and encode_tool together.",
      )
    }
    if extension.encode_tool_choice is Some(_) {
      guard has_tool_encoder else {
        fail(
          "Open Responses extension \{extension.id} cannot provide encode_tool_choice without tool_type and encode_tool.",
        )
      }
    }
    if has_tool_type && has_tool_encoder {
      assert_namespaced_open_responses_type(
        extension_id=extension.id,
        namespace_prefix~,
        type_name=extension.tool_type.unwrap(),
        field="tool_type",
      )
      register_unique_extension(
        registry~,
        extension~,
        key=extension.id,
        field="provider-tool id",
      )
      register_unique_extension(
        registry~,
        extension~,
        key=extension.tool_type.unwrap(),
        field="toolType",
      )
    }
    let has_item_types = extension.item_types is Some(_)
    let has_item_decoder = extension.decode_item is Some(_)
    guard has_item_types == has_item_decoder else {
      fail(
        "Open Responses extension \{extension.id} must provide item_types and decode_item together.",
      )
    }
    if extension.encode_input_item is Some(_) {
      guard has_item_decoder else {
        fail(
          "Open Responses extension \{extension.id} cannot provide encode_input_item without item_types and decode_item.",
        )
      }
    }
    if has_item_types && has_item_decoder {
      for item_type in extension.item_types.unwrap() {
        assert_namespaced_open_responses_type(
          extension_id=extension.id,
          namespace_prefix~,
          type_name=item_type,
          field="item_types entry",
        )
        register_unique_extension(
          registry~,
          extension~,
          key=item_type,
          field="itemTypes",
        )
      }
    }
    let has_event_types = extension.event_types is Some(_)
    let has_event_decoder = extension.decode_event is Some(_)
    guard has_event_types == has_event_decoder else {
      fail(
        "Open Responses extension \{extension.id} must provide event_types and decode_event together.",
      )
    }
    if has_event_types && has_event_decoder {
      for event_type in extension.event_types.unwrap() {
        assert_namespaced_open_responses_type(
          extension_id=extension.id,
          namespace_prefix~,
          type_name=event_type,
          field="event_types entry",
        )
        register_unique_extension(
          registry~,
          extension~,
          key=event_type,
          field="eventTypes",
        )
      }
    }
  }
  registry
}

///|
/// Look up the extension registered for one namespaced event type.
pub fn OpenResponsesExtensionRegistry::event_extension(
  self : OpenResponsesExtensionRegistry,
  event_type : String,
) -> OpenResponsesExtension? {
  self.by_event_type.get(event_type)
}

///|
/// Look up the extension registered for one namespaced item type.
pub fn OpenResponsesExtensionRegistry::item_extension(
  self : OpenResponsesExtensionRegistry,
  item_type : String,
) -> OpenResponsesExtension? {
  self.by_item_type.get(item_type)
}

///|
/// Look up the extension registered for one provider-tool id.
pub fn OpenResponsesExtensionRegistry::provider_tool_extension(
  self : OpenResponsesExtensionRegistry,
  tool_id : String,
) -> OpenResponsesExtension? {
  self.by_provider_tool_id.get(tool_id)
}

///|
/// Return whether a decoded chunk is a namespaced extension event: its
/// `type` is namespaced and it carries a `sequence_number`.
pub fn is_open_responses_extension_event(json : Json) -> Bool {
  match json {
    { "type": String(type_name), "sequence_number": Number(_, ..), .. } =>
      is_namespaced_open_responses_type(type_name)
    _ => false
  }
}

///|
/// Return whether a decoded output item is a namespaced extension item:
/// namespaced `type` plus string `id` and `status`.
pub fn is_open_responses_extension_item(item : Json) -> Bool {
  let type_name = match item {
    { "type": String(value), .. } => value
    _ => return false
  }
  guard is_namespaced_open_responses_type(type_name) else { return false }
  match item {
    { "id": String(_), "status": String(_), .. } => true
    _ => false
  }
}

///|
/// Build the custom replay carrier that preserves the original wire item
/// alongside the decoded content parts.
pub fn open_responses_extension_replay_carrier(
  extension~ : OpenResponsesExtension,
  item~ : Json,
  provider_options_name~ : String,
) -> @provider.LanguageModelV4Content {
  @provider.LanguageModelV4Content::custom(
    kind="open-responses.extension-replay",
    provider_metadata=Map([
      (
        provider_options_name,
        { "openResponsesExtension": { "id": extension.id, "item": item } },
      ),
    ]),
  )
}
