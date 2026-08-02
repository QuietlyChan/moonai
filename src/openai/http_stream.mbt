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
async fn OpenAICompatibleModel::stream_chat(
  self : OpenAICompatibleModel,
  options : @moonai.ChatCallOptions,
  on_event : async (@moonai.StreamEvent) -> Unit,
) -> @moonai.ChatResponse {
  let body = encode_chat_request(
    self.model_id,
    options,
    preserve_reasoning=self.preserve_reasoning,
  )
  let client = @http.post_stream(
    self.chat_completions_url(),
    headers=self.request_headers(),
  )
  defer client.close()
  client.write(body.stringify())
  let response = with_idle_timeout(
    self.idle_timeout_ms,
    "\{self.provider_name} response headers",
    () => client.end_request(),
  )
  guard response.code >= 200 && response.code < 300 else {
    let error_body = client.read_all().text()
    fail("\{self.provider_name} API error \{response.code}: \{error_body}")
  }
  on_event(@moonai.StreamStart)
  let decoder = OpenAIStreamDecoder::new()
  for ;; {
    match read_stream_line(client, self.idle_timeout_ms) {
      Some(Some(raw)) => {
        let batch = decoder.feed_line(raw)
        emit_batch(batch, on_event)
        if batch.done {
          return decoder.response()
        }
      }
      Some(None) => {
        let batch = decoder.flush_buffered()
        emit_batch(batch, on_event)
        if batch.done {
          return decoder.response()
        }
        fail("\{self.provider_name} stream ended before [DONE]")
      }
      None => {
        let batch = decoder.flush_buffered()
        emit_batch(batch, on_event)
        if batch.done {
          return decoder.response()
        }
        fail("\{self.provider_name} stream idle for \{self.idle_timeout_ms}ms")
      }
    }
  }
}
