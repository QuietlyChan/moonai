///|
/// Buffer kept back while streaming so a closing markdown fence that
/// arrives split across deltas is still stripped.
const EXTRACT_JSON_SUFFIX_BUFFER_SIZE : Int = 12

///|
priv enum ExtractJsonPhase {
  ExtractPrefix
  ExtractStreaming
  ExtractBuffering
}

///|
priv struct ExtractJsonTextBlock {
  start_event : @provider.LanguageModelV4StreamPart
  mut phase : ExtractJsonPhase
  buffer : StringBuilder
  mut prefix_stripped : Bool
}

///|
fn extract_json_rtrim(text : String) -> String {
  let view = text
  let mut end = view.length()
  while end > 0 {
    let ch = view[end - 1]
    if ch == ' ' ||
      ch == '\t' ||
      ch == '\n' ||
      ch == '\r' ||
      ch == '\u{0b}' ||
      ch == '\u{0c}' {
      end = end - 1
    } else {
      break
    }
  }
  text[:end].to_owned()
}

///|
fn extract_json_strip_suffix(text : String) -> String {
  // \n?```\s*$ — a closing fence, optionally preceded by one newline, with
  // trailing whitespace absorbed either way.
  let trimmed = extract_json_rtrim(text)
  if trimmed.has_suffix("```") {
    let head = trimmed[:trimmed.length() - 3].to_owned()
    let head_trimmed = extract_json_rtrim(head)
    if head.has_suffix("\n") {
      head_trimmed
    } else {
      head_trimmed
    }
  } else {
    trimmed
  }
}

///|
/// Strip an opening markdown fence (``` or ```json plus the following
/// newline) when the text starts with one; otherwise return the text.
fn extract_json_strip_prefix(text : String) -> String {
  guard text.has_prefix("```") else { return text }
  match text.find("\n") {
    Some(newline_index) if newline_index >= 3 => {
      let header = text[:newline_index].to_owned()
      let header_body = extract_json_rtrim(header)
      if header_body == "```" || header_body == "```json" {
        text[newline_index + 1:].to_owned()
      } else {
        text
      }
    }
    _ => text
  }
}

///|
/// Default transform: strip markdown code fences from both ends and trim.
fn extract_json_default_transform(text : String) -> String {
  let stripped = extract_json_strip_prefix(text)
  let suffix_stripped = extract_json_strip_suffix(stripped)
  suffix_stripped.trim().to_owned()
}

///|
/// Extract-JSON middleware.
///
/// Strips markdown code fences (or applies a custom transform) from text
/// content. Useful with structured-output models that wrap JSON responses
/// in code blocks. Streaming keeps at most a small suffix buffer back so
/// closing fences split across deltas are still removed; custom transforms
/// buffer the whole text block and transform at its end.
pub fn extract_json_middleware(
  transform? : (String) -> String,
) -> @provider.LanguageModelV4Middleware {
  let custom = transform is Some(_)
  let transform = match transform {
    Some(value) => value
    None => extract_json_default_transform
  }
  @provider.LanguageModelV4Middleware::new(
    wrap_generate=async fn(context) {
      let result = (context.do_generate)()
      let content : Array[@provider.LanguageModelV4Content] = []
      for part in result.content {
        match part {
          @provider.V4TextOutput(value) =>
            content.push(
              @provider.LanguageModelV4Content::text(transform(value.text)),
            )
          other => content.push(other)
        }
      }
      { ..result, content, }
    },
    wrap_stream=async fn(context) {
      let blocks : Map[String, ExtractJsonTextBlock] = Map([])
      let emit = async fn(part : @provider.LanguageModelV4StreamPart) -> Unit {
        match part {
          @provider.V4TextStart(id~, ..) =>
            blocks[id] = {
              start_event: part,
              phase: if custom {
                ExtractBuffering
              } else {
                ExtractPrefix
              },
              buffer: StringBuilder(),
              prefix_stripped: false,
            }
          @provider.V4TextDelta(id~, delta~, provider_metadata~) => {
            let block = match blocks.get(id) {
              Some(value) => value
              None => {
                (context.emit)(part)
                return
              }
            }
            block.buffer.write_string(delta)
            let buffered = block.buffer.to_string()
            if block.phase is ExtractPrefix {
              // Decide whether the block opens with a code fence.
              if buffered.length() > 0 && !buffered.has_prefix("`") {
                block.phase = ExtractStreaming
                (context.emit)(block.start_event)
              } else if buffered.has_prefix("```") && buffered.contains("\n") {
                match extract_json_strip_prefix(buffered) {
                  stripped if stripped != buffered => {
                    block.buffer.reset()
                    block.buffer.write_string(stripped)
                    block.prefix_stripped = true
                    block.phase = ExtractStreaming
                    (context.emit)(block.start_event)
                  }
                  _ => {
                    block.phase = ExtractStreaming
                    (context.emit)(block.start_event)
                  }
                }
              } else if buffered.length() >= 3 && !buffered.has_prefix("```") {
                block.phase = ExtractStreaming
                (context.emit)(block.start_event)
              }
            }
            if block.phase is ExtractStreaming &&
              block.buffer.to_string().length() >
              EXTRACT_JSON_SUFFIX_BUFFER_SIZE {
              let buffered = block.buffer.to_string()
              let keep = EXTRACT_JSON_SUFFIX_BUFFER_SIZE
              let to_stream = buffered[:buffered.length() - keep].to_owned()
              block.buffer.reset()
              block.buffer.write_string(
                buffered[buffered.length() - keep:].to_owned(),
              )
              (context.emit)(
                @provider.V4TextDelta(id~, delta=to_stream, provider_metadata~),
              )
            }
          }
          @provider.V4TextEnd(id~, provider_metadata~) => {
            let block = match blocks.get(id) {
              Some(value) => value
              None => {
                (context.emit)(part)
                return
              }
            }
            if !(block.phase is ExtractStreaming) {
              (context.emit)(block.start_event)
            }
            let buffered = block.buffer.to_string()
            let remaining = if block.phase is ExtractBuffering {
              transform(buffered)
            } else if block.prefix_stripped {
              extract_json_strip_suffix(buffered)
            } else if block.phase is ExtractPrefix {
              transform(buffered)
            } else {
              extract_json_strip_suffix(buffered)
            }
            if remaining != "" {
              (context.emit)(
                @provider.V4TextDelta(id~, delta=remaining, provider_metadata~),
              )
            }
            (context.emit)(@provider.V4TextEnd(id~, provider_metadata~))
            blocks.remove(id)
          }
          other => (context.emit)(other)
        }
      }
      context.model.do_stream(context.params, emit)
    },
  )
}
