///|
/// MCP Apps capability extension name.
pub const MCP_APP_EXTENSION_NAME : String = "io.modelcontextprotocol/ui"

///|
/// MIME type used for renderable MCP App HTML resources.
pub const MCP_APP_MIME_TYPE : String = "text/html;profile=mcp-app"

///|
/// Legacy flat metadata key used by earlier MCP Apps servers.
pub const MCP_APP_LEGACY_RESOURCE_URI_META_KEY : String = "ui/resourceUri"

///|
/// Client capabilities advertised by hosts that render MCP Apps.
pub let mcp_app_client_capabilities : MCPClientCapabilities = (
  {
    "extensions": {
      "io.modelcontextprotocol/ui": {
        "mimeTypes": ["text/html;profile=mcp-app"],
      },
    },
  } : Json)

///|
/// AI SDK-style accessor for MCP Apps capabilities.
pub fn mcpAppClientCapabilities() -> MCPClientCapabilities {
  mcp_app_client_capabilities
}

///|
/// Normalized MCP App metadata attached to a tool.
pub(all) struct MCPAppToolMeta {
  resource_uri : String?
  model_visible : Bool
  app_visible : Bool
  raw : Json
} derive(Debug, Eq)

///|
/// Content security policy requested by an MCP App resource.
pub(all) struct MCPAppResourceCSP {
  connect_domains : Array[String]
  resource_domains : Array[String]
  frame_domains : Array[String]
  raw : Json
} derive(Debug, Eq)

///|
/// Host rendering metadata attached to an MCP App resource.
pub(all) struct MCPAppResourceMeta {
  prefers_border : Bool?
  csp : MCPAppResourceCSP?
  permissions : Json?
  raw : Json
} derive(Debug, Eq)

///|
/// HTML and metadata needed to render one MCP App.
pub(all) struct MCPAppResource {
  uri : String
  mime_type : String
  html : String
  meta : MCPAppResourceMeta?
} derive(Debug, Eq)

///|
fn visibility_flags(value : Json?) -> (Bool, Bool) {
  guard value is Some(Array(items)) else { return (true, false) }
  let mut model = false
  let mut app = false
  for item in items {
    match item {
      String("model") => model = true
      String("app") => app = true
      _ => ()
    }
  }
  (model, app)
}

///|
/// Read and validate MCP Apps metadata from a tool `_meta` object.
pub fn get_mcp_app_tool_meta(
  meta : Json?,
) -> MCPAppToolMeta? raise MCPClientError {
  guard meta is Some(Object(fields)) else { return None }
  let ui = match fields.get("ui") {
    Some(Object(values)) => Some(values)
    _ => None
  }
  let resource_uri = match ui {
    Some(values) => optional_string(values, "resourceUri")
    None => optional_string(fields, MCP_APP_LEGACY_RESOURCE_URI_META_KEY)
  }
  if resource_uri is Some(uri) && !uri.has_prefix("ui://") {
    raise mcp_error("Invalid MCP App resource URI: " + uri)
  }
  guard ui is Some(_) || resource_uri is Some(_) else { return None }
  let (model_visible, app_visible) = visibility_flags(
    match ui {
      Some(values) => values.get("visibility")
      None => None
    },
  )
  Some({
    resource_uri,
    model_visible,
    app_visible,
    raw: match ui {
      Some(values) => Json::object(values)
      None => Json::empty_object()
    },
  })
}

///|
/// AI SDK-style spelling for `get_mcp_app_tool_meta`.
pub fn getMCPAppToolMeta(meta : Json?) -> MCPAppToolMeta? raise MCPClientError {
  get_mcp_app_tool_meta(meta)
}

///|
/// Return the app resource URI attached to a tool definition.
pub fn get_mcp_app_resource_uri(tool : MCPTool) -> String? raise MCPClientError {
  match get_mcp_app_tool_meta(tool.meta) {
    Some(meta) => meta.resource_uri
    None => None
  }
}

///|
/// AI SDK-style spelling for `get_mcp_app_resource_uri`.
pub fn getMCPAppResourceUri(tool : MCPTool) -> String? raise MCPClientError {
  get_mcp_app_resource_uri(tool)
}

///|
/// Whether a tool definition has a renderable MCP App resource.
pub fn is_mcp_app_tool(tool : MCPTool) -> Bool {
  (get_mcp_app_resource_uri(tool) catch { _ => None }) is Some(_)
}

///|
/// AI SDK-style spelling for `is_mcp_app_tool`.
pub fn isMCPAppTool(tool : MCPTool) -> Bool {
  is_mcp_app_tool(tool)
}

///|
/// Model-visible and app-visible tool definition pages.
pub(all) struct SplitMCPAppToolsResult {
  model_visible : ListToolsResult
  app_visible : ListToolsResult
} derive(Debug, Eq)

///|
/// Split tool definitions according to MCP Apps visibility metadata.
pub fn split_mcp_app_tools(
  definitions : ListToolsResult,
) -> SplitMCPAppToolsResult raise MCPClientError {
  let model : Array[MCPTool] = []
  let app : Array[MCPTool] = []
  for tool in definitions.tools {
    match get_mcp_app_tool_meta(tool.meta) {
      None => model.push(tool)
      Some(meta) => {
        if meta.model_visible {
          model.push(tool)
        }
        if meta.app_visible {
          app.push(tool)
        }
      }
    }
  }
  {
    model_visible: {
      tools: model,
      next_cursor: definitions.next_cursor,
      raw: definitions.raw,
    },
    app_visible: {
      tools: app,
      next_cursor: definitions.next_cursor,
      raw: definitions.raw,
    },
  }
}

///|
/// AI SDK-style spelling for `split_mcp_app_tools`.
pub fn splitMCPAppTools(
  definitions : ListToolsResult,
) -> SplitMCPAppToolsResult raise MCPClientError {
  split_mcp_app_tools(definitions)
}

///|
/// Return unique MCP App resource URIs referenced by tool definitions.
pub fn get_mcp_app_resource_uris(
  definitions : ListToolsResult,
) -> Array[String] raise MCPClientError {
  let result : Array[String] = []
  for tool in definitions.tools {
    if get_mcp_app_resource_uri(tool) is Some(uri) && !result.contains(uri) {
      result.push(uri)
    }
  }
  result
}

///|
fn string_array_field(
  fields : Map[String, Json],
  name : String,
) -> Array[String] {
  let result : Array[String] = []
  if fields.get(name) is Some(Array(items)) {
    for item in items {
      if item is String(value) {
        result.push(value)
      }
    }
  }
  result
}

///|
fn decode_app_resource_meta(meta : Json?) -> MCPAppResourceMeta? {
  guard meta is Some(Object(fields)) && fields.get("ui") is Some(Object(ui)) else {
    return None
  }
  let csp = match ui.get("csp") {
    Some(Object(csp)) =>
      Some({
        connect_domains: string_array_field(csp, "connectDomains"),
        resource_domains: string_array_field(csp, "resourceDomains"),
        frame_domains: string_array_field(csp, "frameDomains"),
        raw: Json::object(csp),
      })
    _ => None
  }
  Some({
    prefers_border: optional_bool(ui, "prefersBorder"),
    csp,
    permissions: ui.get("permissions"),
    raw: Json::object(ui),
  })
}

///|
/// Normalize an MCP resources/read result into a renderable app resource.
pub fn get_mcp_app_resource_from_read_result(
  uri~ : String,
  resource~ : ReadResourceResult,
) -> MCPAppResource raise MCPClientError {
  for content in resource.contents {
    match content {
      MCPTextResource(uri=found, mime_type~, text~, meta~, ..) if found == uri => {
        guard mime_type == Some(MCP_APP_MIME_TYPE) else {
          raise mcp_error("Unsupported MCP App resource MIME type")
        }
        return {
          uri,
          mime_type: MCP_APP_MIME_TYPE,
          html: text,
          meta: decode_app_resource_meta(meta),
        }
      }
      MCPBlobResource(uri=found, mime_type~, blob~, meta~, ..) if found == uri => {
        guard mime_type == Some(MCP_APP_MIME_TYPE) else {
          raise mcp_error("Unsupported MCP App resource MIME type")
        }
        let html = @utf8.decode(@base64.decode(blob, ignore_whitespace=true)) catch {
          error =>
            raise MCPClientError::new(
              message="MCP App resource contains invalid base64 or UTF-8",
              cause=@debug.to_string(error),
            )
        }
        return {
          uri,
          mime_type: MCP_APP_MIME_TYPE,
          html,
          meta: decode_app_resource_meta(meta),
        }
      }
      _ => ()
    }
  }
  raise mcp_error("MCP App resource not found in read result: " + uri)
}

///|
/// Read and normalize one `ui://` MCP App resource.
pub async fn read_mcp_app_resource(
  client~ : MCPClient,
  uri~ : String,
  options? : MCPRequestOptions,
) -> MCPAppResource {
  guard uri.has_prefix("ui://") else {
    raise mcp_error("Unsupported MCP App resource URI: " + uri)
  }
  get_mcp_app_resource_from_read_result(
    uri~,
    resource=client.read_resource(uri~, options?),
  )
}

///|
/// AI SDK-style spelling for `read_mcp_app_resource`.
pub async fn readMCPAppResource(
  client~ : MCPClient,
  uri~ : String,
  options? : MCPRequestOptions,
) -> MCPAppResource {
  read_mcp_app_resource(client~, uri~, options?)
}

///|
fn app_fingerprint_json(resource : MCPAppResource) -> Json {
  let csp = match resource.meta {
    Some(meta) => meta.csp.map(value => value.raw).unwrap_or(Json::null())
    None => Json::null()
  }
  let permissions = match resource.meta {
    Some(meta) => meta.permissions.unwrap_or(Json::null())
    None => Json::null()
  }
  { "html": resource.html, "csp": csp, "permissions": permissions }
}

///|
fn canonical_json(value : Json) -> String {
  match value {
    Object(fields) => {
      let keys : Array[String] = []
      for entry in fields.iter2() {
        keys.push(entry.0)
      }
      keys.sort()
      let entries : Array[String] = []
      for key in keys {
        entries.push(
          Json::string(key).stringify() +
          ":" +
          canonical_json(fields.get(key).unwrap()),
        )
      }
      "{" + entries.join(",") + "}"
    }
    Array(items) =>
      "[" + [ for item in items => canonical_json(item) ].join(",") + "]"
    _ => value.stringify()
  }
}

///|
/// Stable SHA-256 base64url fingerprint over app HTML, CSP, and permissions.
pub fn fingerprint_mcp_app_resource(resource : MCPAppResource) -> String {
  let digest = @mooncry.sha256(
    @utf8.encode(canonical_json(app_fingerprint_json(resource))),
  )
  @base64.encode(digest, padding=false)
  .replace(old="+", new="-")
  .replace(old="/", new="_")
}

///|
/// AI SDK-style spelling for `fingerprint_mcp_app_resource`.
pub fn fingerprintMCPAppResource(resource : MCPAppResource) -> String {
  fingerprint_mcp_app_resource(resource)
}

///|
/// Whether the current MCP App fingerprint differs from a baseline.
pub fn detect_mcp_app_resource_drift(
  current : String,
  baseline : String,
) -> Bool {
  current != baseline
}

///|
/// AI SDK-style spelling for `detect_mcp_app_resource_drift`.
pub fn detectMCPAppResourceDrift(current : String, baseline : String) -> Bool {
  detect_mcp_app_resource_drift(current, baseline)
}
