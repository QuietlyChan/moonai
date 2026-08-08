///|
let agent_instructions : String = "You are the MoonAI Agent Workbench assistant. Answer clearly and concisely. Use the available tools when they help, and report tool results accurately."

///|
fn response_headers(content_type : String) -> Map[String, String] {
  {
    "Content-Type": content_type,
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  }
}

///|
async fn send_json(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
  value : Json,
) -> Unit {
  conn.send_response(
    code,
    reason,
    extra_headers=response_headers("application/json; charset=utf-8"),
  )
  conn.write(value.stringify())
  conn.end_response()
}

///|
async fn send_error(
  conn : @http.ServerConnection,
  code : Int,
  reason : String,
  message : String,
) -> Unit {
  send_json(conn, code, reason, { "error": message })
}

///|
async fn send_options(conn : @http.ServerConnection) -> Unit {
  let headers = response_headers("text/plain; charset=utf-8")
  headers["Content-Length"] = "0"
  conn.send_response(204, "No Content", extra_headers=headers)
  conn.end_response()
}

///|
fn parse_chat_messages(value : Json) -> Array[@ai.ModelMessage] raise {
  let raw_messages = match value {
    { "messages": Array(messages), .. } => messages
    { "prompt": String(prompt), .. } =>
      [({ "role": "user", "content": prompt } : Json)]
    _ => fail("Expected a JSON object with a messages array or prompt string.")
  }
  guard raw_messages.length() > 0 else {
    fail("At least one message is required.")
  }
  guard raw_messages.length() <= 32 else {
    fail("A maximum of 32 messages is supported by this example.")
  }
  let messages : Array[@ai.ModelMessage] = []
  for message in raw_messages {
    match message {
      { "role": String(role), "content": String(content), .. } => {
        let text = content.trim().to_owned()
        guard text != "" else { fail("Message content cannot be empty.") }
        guard text.length() <= 8_000 else {
          fail("Each message is limited to 8,000 characters.")
        }
        match role {
          "user" => messages.push(@ai.ModelMessage::user(text))
          "assistant" => messages.push(@ai.ModelMessage::assistant(text))
          _ => fail("Message roles must be user or assistant.")
        }
      }
      _ => fail("Each message requires string role and content fields.")
    }
  }
  guard messages[messages.length() - 1].role is @provider_utils.ModelUser else {
    fail("The final message must have the user role.")
  }
  messages
}

///|
async fn read_chat_messages(body : &@io.Reader) -> Array[@ai.ModelMessage] {
  parse_chat_messages(@json.parse(body.read_all().text()))
}

///|
fn ui_message_text(parts : Array[Json]) -> String {
  let mut result = ""
  for part in parts {
    match part {
      { "type": "text", "text": String(text), .. } if text != "" => {
        if result != "" {
          result = result + "\n"
        }
        result = result + text
      }
      _ => ()
    }
  }
  result
}

///|
fn ui_message_role(message : Json) -> String? {
  match message {
    { "role": String(role), .. } => Some(role)
    _ => None
  }
}

///|
fn ui_message_id(message : Json) -> String? {
  match message {
    { "id": String(id), .. } => Some(id)
    _ => None
  }
}

///|
fn ui_message_limit(
  messages : Array[Json],
  trigger : String,
  message_id : String?,
) -> Int raise {
  guard trigger == "submit-message" || trigger == "regenerate-message" else {
    fail("Trigger must be submit-message or regenerate-message.")
  }
  if trigger == "submit-message" {
    return messages.length()
  }
  match message_id {
    Some(target_id) => {
      for index, message in messages {
        if ui_message_id(message) == Some(target_id) {
          return if ui_message_role(message) == Some("assistant") {
            index
          } else {
            index + 1
          }
        }
      }
      fail("The message selected for regeneration was not found.")
    }
    None =>
      if messages.length() > 0 &&
        ui_message_role(messages[messages.length() - 1]) == Some("assistant") {
        messages.length() - 1
      } else {
        messages.length()
      }
  }
}

///|
fn parse_ui_chat_messages(value : Json) -> Array[@ai.ModelMessage] raise {
  let (raw_messages, trigger, message_id) = match value {
    {
      "messages": Array(messages),
      "trigger": String(trigger),
      "messageId": String(message_id),
      ..
    } => (messages, trigger, Some(message_id))
    { "messages": Array(messages), "trigger": String(trigger), .. } =>
      (messages, trigger, None)
    { "messages": Array(messages), .. } => (messages, "submit-message", None)
    _ => fail("Expected an AI SDK request with a messages array.")
  }
  guard raw_messages.length() > 0 else {
    fail("At least one UI message is required.")
  }
  guard raw_messages.length() <= 32 else {
    fail("A maximum of 32 UI messages is supported by this example.")
  }
  let limit = ui_message_limit(raw_messages, trigger, message_id)
  let messages : Array[@ai.ModelMessage] = []
  for index, message in raw_messages {
    if index >= limit {
      break
    }
    match message {
      { "role": String(role), "parts": Array(parts), .. } => {
        let text = ui_message_text(parts).trim().to_owned()
        if text == "" && role == "assistant" {
          continue
        }
        guard text != "" else {
          fail("User UI messages must contain a non-empty text part.")
        }
        guard text.length() <= 8_000 else {
          fail("Each UI message is limited to 8,000 characters.")
        }
        match role {
          "user" => messages.push(@ai.ModelMessage::user(text))
          "assistant" => messages.push(@ai.ModelMessage::assistant(text))
          _ => fail("UI message roles must be user or assistant.")
        }
      }
      _ => fail("Each UI message requires role and parts fields.")
    }
  }
  guard messages.length() > 0 else {
    fail("No messages remain to generate from.")
  }
  guard messages[messages.length() - 1].role is @provider_utils.ModelUser else {
    fail("The final UI message must have the user role.")
  }
  messages
}

///|
fn finish_reason_name(reason : @provider.LanguageModelV4FinishReason) -> String {
  match reason.unified {
    @provider.V4FinishStop => "stop"
    @provider.V4FinishLength => "length"
    @provider.V4FinishContentFilter => "content-filter"
    @provider.V4FinishToolCalls => "tool-calls"
    @provider.V4FinishError => "error"
    @provider.V4FinishOther => "other"
  }
}

///|
fn tool_calls_json(calls : Array[@ai.GenerateTextToolCall]) -> Json {
  Json::array(
    [
      for call in calls => {
        {
          "toolCallId": call.tool_call_id,
          "toolName": call.tool_name,
          "input": call.input,
          "providerExecuted": call.provider_executed,
          "invalid": call.invalid,
        }
      }
    ],
  )
}

///|
fn tool_results_json(results : Array[@ai.GenerateTextToolResult]) -> Json {
  Json::array(
    [
      for result in results => {
        {
          "toolCallId": result.tool_call_id,
          "toolName": result.tool_name,
          "output": result.output,
          "isError": result.is_error,
          "providerExecuted": result.provider_executed,
        }
      }
    ],
  )
}

///|
fn chat_result_json(
  config : @shared.ExampleConfig,
  result : @ai.GenerateTextResult,
) -> Json {
  {
    "text": result.text(),
    "reasoning": result.reasoning(),
    "provider": config.display_provider(),
    "model": config.model_id(),
    "finishReason": finish_reason_name(result.finish_reason),
    "stepCount": result.steps.length(),
    "toolCalls": tool_calls_json(result.tool_calls),
    "toolResults": tool_results_json(result.tool_results),
    "usage": @shared.usage_json(result.total_usage),
  }
}

///|
async fn handle_chat(body : &@io.Reader, conn : @http.ServerConnection) -> Unit {
  let messages = read_chat_messages(body) catch {
    error => {
      send_error(conn, 400, "Bad Request", "Invalid request: \{error}")
      return
    }
  }
  let config = @shared.load_example_config()
  let result = @ai.generate_text(
    config.language_model(),
    messages~,
    instructions=@ai.Instructions::text(agent_instructions),
    tools=@shared.example_tools(),
    stop_when=[@ai.is_step_count(5)],
  ) catch {
    error => {
      send_error(conn, 502, "Bad Gateway", "Model request failed: \{error}")
      return
    }
  }
  send_json(conn, 200, "OK", chat_result_json(config, result))
}

///|
async fn write_ndjson(conn : @http.ServerConnection, event : Json) -> Unit {
  conn.write(event.stringify() + "\n")
  conn.flush()
}

///|
fn sse_event(event : Json) -> String {
  "data: " + event.stringify() + "\n\n"
}

///|
async fn write_sse(conn : @http.ServerConnection, event : Json) -> Unit {
  conn.write(sse_event(event))
  conn.flush()
}

///|
async fn finish_sse(conn : @http.ServerConnection) -> Unit {
  conn.write("data: [DONE]\n\n")
  conn.flush()
  conn.end_response()
}

///|
async fn write_provider_event(
  conn : @http.ServerConnection,
  event : @provider.LanguageModelV4StreamPart,
) -> Unit {
  match event {
    @provider.V4TextDelta(id~, delta~, ..) =>
      write_ndjson(conn, { "type": "text-delta", "id": id, "delta": delta })
    @provider.V4ReasoningDelta(id~, delta~, ..) =>
      write_ndjson(conn, { "type": "reasoning-delta", "id": id, "delta": delta })
    @provider.V4ToolInputStart(id~, tool_name~, title~, ..) => {
      let display_title = match title {
        Some(value) => value
        None => tool_name
      }
      write_ndjson(conn, {
        "type": "tool-input-start",
        "toolCallId": id,
        "toolName": tool_name,
        "title": display_title,
      })
    }
    @provider.V4ToolInputDelta(id~, delta~, ..) =>
      write_ndjson(conn, {
        "type": "tool-input-delta",
        "toolCallId": id,
        "delta": delta,
      })
    @provider.V4ToolInputEnd(id~, ..) =>
      write_ndjson(conn, { "type": "tool-input-end", "toolCallId": id })
    @provider.V4ToolCallReady(call) =>
      write_ndjson(conn, {
        "type": "tool-call",
        "toolCallId": call.tool_call_id,
        "toolName": call.tool_name,
        "inputText": call.input,
        "providerExecuted": call.provider_executed,
      })
    @provider.V4ToolResultReady(result) =>
      write_ndjson(conn, {
        "type": "provider-tool-result",
        "toolCallId": result.tool_call_id,
        "toolName": result.tool_name,
        "output": result.result,
        "isError": result.is_error,
      })
    @provider.V4Finish(usage~, reason~, ..) =>
      write_ndjson(conn, {
        "type": "step-finish",
        "finishReason": finish_reason_name(reason),
        "usage": @shared.usage_json(usage),
      })
    @provider.V4Error(error) =>
      write_ndjson(conn, {
        "type": "provider-error",
        "message": error.message,
        "data": error.data.unwrap_or(Json::null()),
      })
    _ => ()
  }
}

///|
async fn handle_chat_stream(
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let messages = read_chat_messages(body) catch {
    error => {
      send_error(conn, 400, "Bad Request", "Invalid request: \{error}")
      return
    }
  }
  let config = @shared.load_example_config()
  conn.send_response(
    200,
    "OK",
    extra_headers=response_headers("application/x-ndjson; charset=utf-8"),
  )
  write_ndjson(conn, {
    "type": "metadata",
    "provider": config.display_provider(),
    "model": config.model_id(),
  })
  let tools = @shared.example_tools(sink=event => write_ndjson(conn, event))
  let result = @ai.stream_text(
    config.language_model(),
    messages~,
    instructions=@ai.Instructions::text(agent_instructions),
    tools~,
    stop_when=[@ai.is_step_count(5)],
    on_event=event => write_provider_event(conn, event),
  ) catch {
    error => {
      write_ndjson(conn, { "type": "error", "message": "\{error}" })
      conn.end_response()
      return
    }
  }
  write_ndjson(conn, {
    "type": "finish",
    "text": result.text(),
    "reasoning": result.reasoning(),
    "finishReason": finish_reason_name(result.finish_reason),
    "stepCount": result.steps.length(),
    "toolCalls": tool_calls_json(result.tool_calls),
    "toolResults": tool_results_json(result.tool_results),
    "usage": @shared.usage_json(result.total_usage),
  })
  conn.end_response()
}

///|
async fn write_use_chat_tool_event(
  conn : @http.ServerConnection,
  event : Json,
) -> Unit {
  match event {
    {
      "type": "tool-execution-result",
      "toolCallId": String(tool_call_id),
      "payload": output,
      ..
    } =>
      write_sse(conn, {
        "type": "tool-output-available",
        "toolCallId": tool_call_id,
        "output": output,
        "dynamic": true,
      })
    _ => ()
  }
}

///|
async fn write_tool_input_available(
  conn : @http.ServerConnection,
  call : @provider.LanguageModelV4ToolCall,
) -> Unit {
  let input = @json.parse(call.input) catch {
    error => {
      write_sse(conn, {
        "type": "tool-input-error",
        "toolCallId": call.tool_call_id,
        "toolName": call.tool_name,
        "input": call.input,
        "errorText": "Invalid tool input JSON: \{error}",
        "providerExecuted": call.provider_executed,
        "dynamic": true,
      })
      return
    }
  }
  write_sse(conn, {
    "type": "tool-input-available",
    "toolCallId": call.tool_call_id,
    "toolName": call.tool_name,
    "input": input,
    "providerExecuted": call.provider_executed,
    "dynamic": true,
  })
}

///|
struct UseChatStreamState {
  mut step_open : Bool
}

///|
async fn write_use_chat_provider_event(
  conn : @http.ServerConnection,
  state : UseChatStreamState,
  event : @provider.LanguageModelV4StreamPart,
) -> Unit {
  match event {
    @provider.V4StreamStart(..) => {
      if state.step_open {
        write_sse(conn, { "type": "finish-step" })
      }
      write_sse(conn, { "type": "start-step" })
      state.step_open = true
    }
    @provider.V4TextStart(id~, ..) =>
      write_sse(conn, { "type": "text-start", "id": id })
    @provider.V4TextDelta(id~, delta~, ..) =>
      write_sse(conn, { "type": "text-delta", "id": id, "delta": delta })
    @provider.V4TextEnd(id~, ..) =>
      write_sse(conn, { "type": "text-end", "id": id })
    @provider.V4ReasoningStart(id~, ..) =>
      write_sse(conn, { "type": "reasoning-start", "id": id })
    @provider.V4ReasoningDelta(id~, delta~, ..) =>
      write_sse(conn, { "type": "reasoning-delta", "id": id, "delta": delta })
    @provider.V4ReasoningEnd(id~, ..) =>
      write_sse(conn, { "type": "reasoning-end", "id": id })
    @provider.V4ToolInputStart(id~, tool_name~, provider_executed~, title~, ..) => {
      let event : Map[String, Json] = {
        "type": "tool-input-start",
        "toolCallId": id,
        "toolName": tool_name,
        "providerExecuted": provider_executed,
        "dynamic": true,
      }
      match title {
        Some(value) => event["title"] = Json::string(value)
        None => ()
      }
      write_sse(conn, Json::object(event))
    }
    @provider.V4ToolInputDelta(id~, delta~, ..) =>
      write_sse(conn, {
        "type": "tool-input-delta",
        "toolCallId": id,
        "inputTextDelta": delta,
      })
    @provider.V4ToolCallReady(call) => write_tool_input_available(conn, call)
    @provider.V4ToolResultReady(result) =>
      write_sse(conn, {
        "type": "tool-output-available",
        "toolCallId": result.tool_call_id,
        "output": result.result,
        "providerExecuted": true,
        "preliminary": result.preliminary,
        "dynamic": true,
      })
    @provider.V4Finish(..) => ()
    @provider.V4Error(error) =>
      write_sse(conn, { "type": "error", "errorText": error.message })
    _ => ()
  }
}

///|
fn use_chat_message_id(request : Json) -> String {
  let chat_id = match request {
    { "id": String(value), .. } if value != "" => value
    _ => "chat"
  }
  "moonai-" + chat_id + "-" + @env.now().to_string()
}

///|
async fn handle_use_chat(
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  let request = @json.parse(body.read_all().text()) catch {
    error => {
      send_error(conn, 400, "Bad Request", "Invalid JSON request: \{error}")
      return
    }
  }
  let messages = parse_ui_chat_messages(request) catch {
    error => {
      send_error(conn, 400, "Bad Request", "Invalid AI SDK request: \{error}")
      return
    }
  }
  let config = @shared.load_example_config()
  let headers = response_headers("text/event-stream")
  headers["Connection"] = "keep-alive"
  headers["X-Accel-Buffering"] = "no"
  headers["x-vercel-ai-ui-message-stream"] = "v1"
  conn.send_response(200, "OK", extra_headers=headers)
  write_sse(conn, {
    "type": "start",
    "messageId": use_chat_message_id(request),
    "messageMetadata": {
      "provider": config.display_provider(),
      "model": config.model_id(),
    },
  })
  let tools = @shared.example_tools(sink=event => {
    write_use_chat_tool_event(conn, event)
  })
  let stream_state : UseChatStreamState = { step_open: false }
  let result = @ai.stream_text(
    config.language_model(),
    messages~,
    instructions=@ai.Instructions::text(agent_instructions),
    tools~,
    stop_when=[@ai.is_step_count(5)],
    on_event=event => write_use_chat_provider_event(conn, stream_state, event),
  ) catch {
    error => {
      write_sse(conn, {
        "type": "error",
        "errorText": "Model request failed: \{error}",
      })
      finish_sse(conn)
      return
    }
  }
  if stream_state.step_open {
    write_sse(conn, { "type": "finish-step" })
  }
  write_sse(conn, {
    "type": "finish",
    "finishReason": finish_reason_name(result.finish_reason),
    "messageMetadata": {
      "provider": config.display_provider(),
      "model": config.model_id(),
      "stepCount": result.steps.length(),
      "usage": @shared.usage_json(result.total_usage),
    },
  })
  finish_sse(conn)
}

///|
async fn frontend_file(name : String) -> String? {
  let configured = @env.get_env_var("MOONAI_FRONTEND_DIR")
  let roots = match configured {
    Some(value) => [value]
    None => ["examples/web_agent/frontend", "web_agent/frontend"]
  }
  for root in roots {
    let path = root + "/" + name
    if @fs.exists(path) {
      return Some(path)
    }
  }
  None
}

///|
fn embedded_frontend(name : String) -> String? {
  match name {
    "index.html" => Some(embedded_index_html)
    "app.js" => Some(embedded_app_js)
    "styles.css" => Some(embedded_styles_css)
    _ => None
  }
}

///|
async fn serve_frontend(
  conn : @http.ServerConnection,
  name : String,
  content_type : String,
) -> Unit {
  let content = match frontend_file(name) {
    Some(path) => @fs.read_file(path).text()
    None =>
      match embedded_frontend(name) {
        Some(value) => value
        None => {
          send_error(conn, 404, "Not Found", "Frontend asset not found.")
          return
        }
      }
  }
  let headers = response_headers(content_type)
  headers["Cache-Control"] = "no-cache"
  conn.send_response(200, "OK", extra_headers=headers)
  conn.write(content)
  conn.end_response()
}

///|
async fn handle_request(
  request : @http.Request,
  body : &@io.Reader,
  conn : @http.ServerConnection,
) -> Unit {
  if request.meth is @http.Options {
    send_options(conn)
    return
  }
  match (request.meth, request.path) {
    (@http.Get, "/api/health") => {
      let config = @shared.load_example_config()
      send_json(conn, 200, "OK", {
        "status": "ok",
        "provider": config.display_provider(),
        "model": config.model_id(),
        "demo": config.is_demo(),
      })
    }
    (@http.Post, "/api/chat") => handle_chat(body, conn)
    (@http.Post, "/api/chat/stream") => handle_chat_stream(body, conn)
    (@http.Post, "/api/use-chat") => handle_use_chat(body, conn)
    (@http.Get, "/") | (@http.Get, "/index.html") =>
      serve_frontend(conn, "index.html", "text/html; charset=utf-8")
    (@http.Get, "/app.js") =>
      serve_frontend(conn, "app.js", "text/javascript; charset=utf-8")
    (@http.Get, "/styles.css") =>
      serve_frontend(conn, "styles.css", "text/css; charset=utf-8")
    (@http.Get, "/favicon.ico") => {
      let headers = response_headers("image/x-icon")
      headers["Content-Length"] = "0"
      conn.send_response(204, "No Content", extra_headers=headers)
      conn.end_response()
    }
    (@http.Get, _) | (@http.Post, _) =>
      send_error(conn, 404, "Not Found", "Route not found.")
    _ => send_error(conn, 405, "Method Not Allowed", "Method not allowed.")
  }
}

///|
fn configured_port() -> Int {
  match @env.get_env_var("MOONAI_PORT") {
    Some(value) => @string.parse_int(value) catch { _ => 8080 }
    None => 8080
  }
}

///|
async fn main {
  let host = @env.get_env_var("MOONAI_HOST").unwrap_or("127.0.0.1")
  let port = configured_port()
  let server = @http.Server(@socket.Addr::parse(host + ":" + port.to_string()))
  let config = @shared.load_example_config()
  println(
    "MoonAI Agent Workbench: http://" +
    host +
    ":" +
    port.to_string() +
    " (provider=" +
    config.display_provider() +
    ", model=" +
    config.model_id() +
    ")",
  )
  server.run_forever(handle_request) catch {
    error => println("Server stopped: \{error}")
  }
}
