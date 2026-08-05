///|

///|
/// Alibaba prompt-cache control attached to a message or content part.
///
/// Alibaba currently documents `ephemeral`, while the open string keeps the
/// type forward-compatible with provider additions, matching AI SDK.
pub(all) struct AlibabaCacheControl {
  cache_type : String
} derive(Debug, Eq)

///|
/// Construct a typed Alibaba cache-control marker.
pub fn AlibabaCacheControl::new(cache_type~ : String) -> AlibabaCacheControl {
  { cache_type, }
}

///|
/// Convert a cache-control marker into Alibaba's provider-options namespace.
/// The result can be attached with
/// `LanguageModelMessage::with_provider_options` or
/// `LanguageModelContentPart::with_provider_options`.
pub fn AlibabaCacheControl::to_provider_options(
  self : AlibabaCacheControl,
) -> Map[String, Json] {
  { "alibaba": { "cacheControl": { "type": self.cache_type } } }
}

///|
fn alibaba_cache_control(options : Map[String, Json]) -> Json? {
  match options.get("alibaba") {
    Some(Object(values)) =>
      match values.get("cacheControl") {
        Some(Null) | None =>
          match values.get("cache_control") {
            Some(Null) | None => None
            Some(value) => Some(value)
          }
        Some(value) => Some(value)
      }
    _ => None
  }
}

///|
fn record_alibaba_cache_control(
  value : Json?,
  count : Ref[Int],
  warnings : Array[@provider.Warning],
) -> Json? {
  guard value is Some(cache_control) else { return None }
  count.val = count.val + 1
  if count.val > 4 {
    warnings.push(
      @provider.Warning::Other(
        message="Max breakpoint limit exceeded. Only the last 4 cache markers will take effect.",
      ),
    )
  }
  Some(cache_control)
}

///|
fn alibaba_text_block(text : String, cache_control : Json?) -> Json {
  Json::object(
    Map(
      [
        ("type", Json::string("text")),
        ("text", Json::string(text)),
        ..if cache_control is Some(value) {
          [("cache_control", value)]
        },
      ],
    ),
  )
}

///|
fn alibaba_user_content_part(
  part : @provider.LanguageModelContentPart,
  cache_control : Json?,
) -> Json raise {
  let fields : Map[String, Json] = match part.without_provider_options() {
    @provider.Text(value) =>
      Map([("type", Json::string("text")), ("text", Json::string(value))])
    @provider.ImageUrl(url) =>
      Map([
        ("type", Json::string("image_url")),
        ("image_url", ({ "url": url } : Json)),
      ])
    @provider.ImageData(data~, media_type~) =>
      Map([
        ("type", Json::string("image_url")),
        (
          "image_url",
          (
            {
              "url": "data:\{@provider_utils.resolve_full_media_type(media_type, data)};base64,\{data}",
            } : Json),
        ),
      ])
    @provider.FileUrl(url~, media_type~, filename=_) => {
      guard @provider_utils.get_top_level_media_type(media_type) == "image" else {
        fail("Alibaba Chat supports image URL file parts only")
      }
      Map([
        ("type", Json::string("image_url")),
        ("image_url", ({ "url": url } : Json)),
      ])
    }
    @provider.FileData(data~, media_type~, filename=_) => {
      guard @provider_utils.get_top_level_media_type(media_type) == "image" else {
        fail("Alibaba Chat supports image file parts only")
      }
      let full_media_type = @provider_utils.resolve_full_media_type(
        media_type, data,
      )
      Map([
        ("type", Json::string("image_url")),
        (
          "image_url",
          ({ "url": "data:\{full_media_type};base64,\{data}" } : Json),
        ),
      ])
    }
    @provider.FileReference(..) =>
      fail("Alibaba Chat does not accept file provider references")
    @provider.AudioData(..) =>
      fail("Alibaba Chat does not accept audio content parts")
    @provider.Reasoning(_)
    | @provider.ReasoningFileUrl(..)
    | @provider.ReasoningFileData(..)
    | @provider.Custom(..)
    | @provider.ToolCallPart(_)
    | @provider.ToolResultPart(_)
    | @provider.ToolApprovalRequestPart(_)
    | @provider.ToolApprovalResponsePart(_) =>
      fail("Alibaba Chat does not accept this content part")
    @provider.ProviderOptions(part~, ..) =>
      return alibaba_user_content_part(part, cache_control)
  }
  if cache_control is Some(value) {
    fields["cache_control"] = value
  }
  Json::object(fields)
}

///|
fn alibaba_assistant_text(
  message : @provider.LanguageModelMessage,
) -> String raise {
  let text = StringBuilder::new()
  if message.parts.length() > 0 {
    for part in message.parts {
      match part.without_provider_options() {
        @provider.Text(value) => text.write_string(value)
        @provider.ToolCallPart(_) => ()
        _ => fail("Alibaba assistant messages support text content parts only")
      }
    }
  } else {
    text.write_string(message.content)
  }
  if message.reasoning_content is Some(value) {
    text.write_string(value)
  }
  text.to_string()
}

///|
fn alibaba_tool_call(call : @provider.ToolCall) -> Json {
  {
    "id": call.id,
    "type": "function",
    "function": { "name": call.name, "arguments": call.arguments },
  }
}

///|
fn alibaba_tool_text(message : @provider.LanguageModelMessage) -> String raise {
  guard message.parts.length() > 0 else { return message.content }
  let text = StringBuilder::new()
  for part in message.parts {
    match part.without_provider_options() {
      @provider.Text(value) => text.write_string(value)
      _ => fail("Alibaba tool results support text content parts only")
    }
  }
  text.to_string()
}

///|
/// Serialize one structured tool result for Alibaba's Chat Completions
/// endpoint. The endpoint accepts a textual `tool` message, so JSON and
/// multimodal outputs use the normalized JSON representation.
fn alibaba_tool_result_text(
  output : @provider.LanguageModelToolResultOutput,
) -> String {
  match output {
    @provider.LanguageModelToolTextOutput(value~, ..)
    | @provider.LanguageModelToolErrorText(value~, ..) => value
    @provider.LanguageModelToolExecutionDenied(reason~, ..) =>
      reason.unwrap_or("Tool call execution denied.")
    @provider.LanguageModelToolJsonOutput(value~, ..)
    | @provider.LanguageModelToolErrorJson(value~, ..) => value.stringify()
    @provider.LanguageModelToolContent(..) => output.to_json().stringify()
  }
}

///|
/// Convert provider-neutral messages using Alibaba's dedicated prompt rules.
/// Transport and response decoding remain shared with `openai_compatible`.
pub fn alibaba_prompt_converter(
  messages : Array[@provider.LanguageModelMessage],
  _preserve_reasoning : Bool,
  _provider_name : String,
) -> @openai_compatible.OpenAICompatiblePromptConversion raise {
  let converted : Array[Json] = []
  let warnings : Array[@provider.Warning] = []
  let cache_breakpoints = Ref(0)
  for message in messages {
    let message_cache = alibaba_cache_control(message.provider_options)
    match message.role {
      @provider.System => {
        let cache_control = record_alibaba_cache_control(
          message_cache, cache_breakpoints, warnings,
        )
        converted.push({
          "role": "system",
          "content": match cache_control {
            Some(_) =>
              Json::array([alibaba_text_block(message.content, cache_control)])
            None => Json::string(message.content)
          },
        })
      }
      @provider.User => {
        let parts = if message.parts.length() > 0 {
          message.parts
        } else {
          [@provider.LanguageModelContentPart::text(message.content)]
        }
        let content : Array[Json] = []
        for index, part in parts {
          let part_cache = alibaba_cache_control(part.provider_options())
          let resolved_cache = if part_cache is Some(_) {
            part_cache
          } else if index == parts.length() - 1 {
            message_cache
          } else {
            None
          }
          content.push(
            alibaba_user_content_part(
              part,
              record_alibaba_cache_control(
                resolved_cache, cache_breakpoints, warnings,
              ),
            ),
          )
        }
        converted.push({ "role": "user", "content": content })
      }
      @provider.Assistant => {
        let tool_calls = message.effective_tool_calls()
        let text = alibaba_assistant_text(message)
        let cache_control = record_alibaba_cache_control(
          message_cache, cache_breakpoints, warnings,
        )
        let fields : Map[String, Json] = Map([
          ("role", Json::string("assistant")),
          (
            "content",
            match cache_control {
              Some(_) => Json::array([alibaba_text_block(text, cache_control)])
              None if tool_calls.length() > 0 && text == "" => Json::null()
              None => Json::string(text)
            },
          ),
        ])
        if tool_calls.length() > 0 {
          fields["tool_calls"] = Json::array(
            [
              for call in tool_calls => alibaba_tool_call(call)
            ],
          )
        }
        converted.push(Json::object(fields))
      }
      @provider.Tool(tool_call_id) => {
        let structured : Array[Json] = []
        for part in message.parts {
          match part.without_provider_options() {
            @provider.ToolResultPart(result) => {
              let result_cache = alibaba_cache_control(result.provider_options)
              let cache_control = record_alibaba_cache_control(
                if result_cache is Some(_) {
                  result_cache
                } else {
                  alibaba_cache_control(message.provider_options)
                },
                cache_breakpoints,
                warnings,
              )
              let content : Json = match cache_control {
                Some(_) =>
                  Json::array([
                    alibaba_text_block(
                      alibaba_tool_result_text(result.output),
                      cache_control,
                    ),
                  ])
                None => Json::string(alibaba_tool_result_text(result.output))
              }
              structured.push(
                Json::object(
                  Map([
                    ("role", Json::string("tool")),
                    ("tool_call_id", Json::string(result.tool_call_id)),
                    ("content", content),
                  ]),
                ),
              )
            }
            @provider.ToolApprovalResponsePart(_) => ()
            _ => ()
          }
        }
        if structured.length() > 0 {
          for item in structured {
            converted.push(item)
          }
          continue
        }
        let part_cache = if message.parts.length() > 0 {
          alibaba_cache_control(
            message.parts[message.parts.length() - 1].provider_options(),
          )
        } else {
          None
        }
        let cache_control = record_alibaba_cache_control(
          if part_cache is Some(_) {
            part_cache
          } else {
            message_cache
          },
          cache_breakpoints,
          warnings,
        )
        let text = alibaba_tool_text(message)
        converted.push({
          "role": "tool",
          "tool_call_id": tool_call_id,
          "content": match cache_control {
            Some(_) => Json::array([alibaba_text_block(text, cache_control)])
            None => Json::string(text)
          },
        })
      }
    }
  }
  { messages: converted, warnings }
}
