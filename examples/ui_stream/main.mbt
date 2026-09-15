///|
/// UI message stream demo: turn a model's V4 stream parts into the UI
/// message chunk protocol (text/reasoning/tool blocks + finish), encoded as
/// SSE `data:` frames — the wire format `useChat` consumes.
async fn main {
  println("== MoonAI UI message stream demo (offline demo model) ==")
  let config = @shared.load_example_config()
  let stream = @ai.UiMessageStream::new()
  let mut saw_finish = false
  let result = @ai.stream_text(
    config.language_model(),
    prompt="Explain MoonAI in one sentence",
    on_event=event => match @ai.ui_message_chunk(event) {
      Some(chunk) => {
        match chunk {
          { "type": "finish", .. } => saw_finish = true
          _ => ()
        }
        stream.enqueue(chunk)
      }
      None => ()
    },
  )
  if !saw_finish {
    stream.enqueue({ "type": "finish", "finishReason": "stop" })
  }
  stream.close()
  println("chunks: \{stream.length()}")
  for chunk in stream.to_chunks() {
    match chunk {
      { "type": String(kind), .. } => println("  [\{kind}]")
      _ => ()
    }
  }
  let sse = stream.to_sse()
  println("sse bytes: \{@debug.to_string(sse.length())} chars")
  println("final text: \{result.text()}")
}
