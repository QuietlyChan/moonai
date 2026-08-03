///|
async fn[T] with_idle_timeout(
  idle_timeout_ms : Int,
  what : String,
  read : async () -> T,
) -> T {
  if idle_timeout_ms <= 0 {
    read()
  } else {
    match @async.with_timeout_opt(idle_timeout_ms, read) {
      Some(value) => value
      None => fail("\{what} idle for \{idle_timeout_ms}ms")
    }
  }
}

///|
async fn read_stream_line(
  reader : @http.Client,
  idle_timeout_ms : Int,
) -> String?? {
  if idle_timeout_ms <= 0 {
    Some(reader.read_until("\n"))
  } else {
    @async.with_timeout_opt(idle_timeout_ms, () => reader.read_until("\n"))
  }
}

///|
async fn emit_batch(
  batch : DecodeBatch,
  on_event : async (@moonai.StreamEvent) -> Unit,
) -> Unit {
  for event in batch.events {
    on_event(event)
  }
}

///|
/// POST a JSON request and drive a provider-specific decoder from its SSE
/// response. This is the shared transport layer used by provider packages.
pub async fn post_json_sse(
  provider_name~ : String,
  url~ : String,
  headers~ : Map[String, String],
  body~ : Json,
  idle_timeout_ms? : Int = 120_000,
  expected_terminator? : String = "stream terminator",
  feed_line~ : (String) -> DecodeBatch raise,
  flush_buffered~ : () -> DecodeBatch raise,
  response~ : () -> @moonai.ChatResponse,
  on_event~ : async (@moonai.StreamEvent) -> Unit,
) -> @moonai.ChatResponse {
  let client = @http.post_stream(url, headers~)
  defer client.close()
  client.write(body.stringify())
  let http_response = with_idle_timeout(
    idle_timeout_ms,
    "\{provider_name} response headers",
    () => client.end_request(),
  )
  guard http_response.code >= 200 && http_response.code < 300 else {
    let error_body = client.read_all().text()
    fail("\{provider_name} API error \{http_response.code}: \{error_body}")
  }
  on_event(@moonai.StreamStart)
  for ;; {
    match read_stream_line(client, idle_timeout_ms) {
      Some(Some(raw)) => {
        let batch = feed_line(raw)
        emit_batch(batch, on_event)
        if batch.done {
          return response()
        }
      }
      Some(None) => {
        let batch = flush_buffered()
        emit_batch(batch, on_event)
        if batch.done {
          return response()
        }
        fail("\{provider_name} stream ended before \{expected_terminator}")
      }
      None => {
        let batch = flush_buffered()
        emit_batch(batch, on_event)
        if batch.done {
          return response()
        }
        fail("\{provider_name} stream idle for \{idle_timeout_ms}ms")
      }
    }
  }
}
