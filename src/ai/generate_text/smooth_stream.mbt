///|
/// Controls how buffered text is split into smooth chunks.
pub(all) enum SmoothChunking {
  /// Stream word by word (AI SDK default).
  SmoothWord
  /// Stream line by line.
  SmoothLine
  /// Stream by a custom regular expression that must not match the empty
  /// string; the non-matching prefix is emitted together with the match.
  SmoothRegexPattern(pattern~ : String)
} derive(Debug, Eq)

///|
/// Stateful smoother for text and reasoning deltas, mirroring AI SDK's
/// `smoothStream`.
///
/// Deltas are buffered and re-emitted at natural word or line boundaries
/// while every non-text event (tool calls, finish, ...) flushes the buffer
/// unchanged. Provider metadata is carried only on the final flush of a
/// buffered segment so it never leaks into unrelated chunks.
pub struct SmoothTextTransformer {
  priv pattern : Regex
  priv mut buffer : String
  priv mut id : String
  priv mut active : Bool
  priv mut kind_is_reasoning : Bool
  priv metadata : Ref[Map[String, Json]]
  priv mut has_metadata : Bool
}

///|
/// Create a smoother for the requested chunking mode.
pub fn SmoothTextTransformer::new(
  chunking? : SmoothChunking = SmoothWord,
) -> SmoothTextTransformer raise {
  let pattern = match chunking {
    SmoothWord => Regex("[^[:space:]]+[[:space:]]+")
    SmoothLine => Regex("\\n+")
    SmoothRegexPattern(pattern~) => Regex(pattern)
  }
  {
    pattern,
    buffer: "",
    id: "",
    active: false,
    kind_is_reasoning: false,
    metadata: Ref(Map([])),
    has_metadata: false,
  }
}

///|
fn SmoothTextTransformer::detect_chunk(self : SmoothTextTransformer) -> String? {
  match self.pattern.execute(self.buffer) {
    Some(matched) => {
      let content = matched.content().to_owned()
      guard content != "" else { return None }
      // Emit the non-matching prefix together with the match so the buffer
      // is fully consumed, matching AI SDK's smoothStream detector contract.
      Some(matched.before().to_owned() + content)
    }
    None => None
  }
}

///|
fn SmoothTextTransformer::flush_into(
  self : SmoothTextTransformer,
  events : Array[@provider.LanguageModelV4StreamPart],
) -> Unit {
  if self.active && (self.buffer != "" || self.has_metadata) {
    let metadata = if self.has_metadata {
      @provider.copy_provider_metadata(self.metadata.val)
    } else {
      Map([])
    }
    events.push(
      if self.kind_is_reasoning {
        @provider.V4ReasoningDelta(
          id=self.id,
          delta=self.buffer,
          provider_metadata=metadata,
        )
      } else {
        @provider.V4TextDelta(
          id=self.id,
          delta=self.buffer,
          provider_metadata=metadata,
        )
      },
    )
  }
  self.buffer = ""
  self.has_metadata = false
  self.metadata.val = Map([])
  self.active = false
}

///|
fn SmoothTextTransformer::process_delta(
  self : SmoothTextTransformer,
  id~ : String,
  delta~ : String,
  metadata~ : Map[String, Json],
  is_reasoning~ : Bool,
) -> Array[@provider.LanguageModelV4StreamPart] {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  if self.active && (self.kind_is_reasoning != is_reasoning || self.id != id) {
    self.flush_into(events)
  }
  self.buffer = self.buffer + delta
  self.id = id
  self.kind_is_reasoning = is_reasoning
  self.active = true
  if metadata.length() > 0 {
    self.metadata.val = @provider.copy_provider_metadata(metadata)
    self.has_metadata = true
  }
  for ;; {
    match self.detect_chunk() {
      Some(chunk) => {
        self.buffer = self.buffer[chunk.length():].to_owned()
        events.push(
          if is_reasoning {
            @provider.V4ReasoningDelta(
              id~,
              delta=chunk,
              provider_metadata=Map([]),
            )
          } else {
            @provider.V4TextDelta(id~, delta=chunk, provider_metadata=Map([]))
          },
        )
      }
      None => break
    }
  }
  events
}

///|
/// Process one stream event and return the smoothed event sequence.
///
/// Non-text events flush the buffer first and then pass through unchanged.
pub fn SmoothTextTransformer::process(
  self : SmoothTextTransformer,
  part : @provider.LanguageModelV4StreamPart,
) -> Array[@provider.LanguageModelV4StreamPart] {
  match part {
    @provider.V4TextDelta(id~, delta~, provider_metadata~) =>
      self.process_delta(
        id~,
        delta~,
        metadata=provider_metadata,
        is_reasoning=false,
      )
    @provider.V4ReasoningDelta(id~, delta~, provider_metadata~) =>
      self.process_delta(
        id~,
        delta~,
        metadata=provider_metadata,
        is_reasoning=true,
      )
    other => {
      let events = self.flush()
      events.push(other)
      events
    }
  }
}

///|
/// Flush any buffered text; call once when the underlying stream ends.
pub fn SmoothTextTransformer::flush(
  self : SmoothTextTransformer,
) -> Array[@provider.LanguageModelV4StreamPart] {
  let events : Array[@provider.LanguageModelV4StreamPart] = []
  self.flush_into(events)
  events
}
