///|
/// Official OpenAI audio transcription model.
priv struct OpenAITranscriptionModel {
  provider_name : String
  base_url : String
  model_id : String
  api_key : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
  websocket_connector : &@provider_utils.WebSocketConnector
}

///|
priv struct OpenAITranscriptionOptions {
  include_fields : Array[String]
  language : String?
  prompt : String?
  temperature : Double?
  timestamp_granularities : Array[String]
  provided : Bool
}

///|
priv struct ParsedOpenAITranscriptionOptions {
  options : OpenAITranscriptionOptions
  warnings : Array[@provider.Warning]
}

///|
priv struct ParsedOpenAITranscriptionStreamOptions {
  language : String?
  delay : String?
  include_values : Array[String]
  warnings : Array[@provider.Warning]
}

///|
fn openai_transcription_model(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
  websocket_connector~ : &@provider_utils.WebSocketConnector,
) -> OpenAITranscriptionModel {
  {
    provider_name: "\{provider_name}.transcription",
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
    api_key,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
    websocket_connector,
  }
}

///|
fn OpenAITranscriptionModel::url(self : OpenAITranscriptionModel) -> String {
  @provider_utils.append_path(self.base_url, "/audio/transcriptions")
}

///|
fn openai_is_realtime_transcription_model(model_id : String) -> Bool {
  model_id == "gpt-realtime-whisper" ||
  model_id.has_prefix("gpt-realtime-whisper-")
}

///|
fn OpenAITranscriptionModel::request_headers(
  self : OpenAITranscriptionModel,
  call_headers : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([("Accept-Encoding", "identity")])
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      ["moonai/openai/\{VERSION}"],
    ),
    call_headers,
  )
}

///|
fn OpenAITranscriptionModel::stream_request_headers(
  self : OpenAITranscriptionModel,
  call_headers : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      ["moonai/openai/\{VERSION}"],
    ),
    call_headers,
  )
}

///|
fn openai_transcription_string_array(
  reader : @provider_utils.ProviderOptionsReader,
  field : String,
  allowed : Array[String],
) -> Array[String] {
  let result : Array[String] = []
  match reader.take_array(field) {
    Some(values) =>
      for value in values {
        match value {
          String(text) if allowed.length() == 0 || allowed.contains(text) =>
            result.push(text)
          _ =>
            reader.add_warning(
              @provider.Warning::Compatibility(
                feature="providerOptions.openai.\{field}",
                details="Expected an array of supported strings; an invalid item was ignored.",
              ),
            )
        }
      }
    None => ()
  }
  result
}

///|
fn parse_openai_transcription_options(
  provider_options : Map[String, Json],
  _provider_name : String,
) -> ParsedOpenAITranscriptionOptions {
  let resolution = resolve_official_openai_provider_options(provider_options)
  let provided = resolution.namespace_key is Some(_)
  let reader = @provider_utils.ProviderOptionsReader::new(
    resolution,
    path="providerOptions.openai",
  )
  let include_fields = openai_transcription_string_array(reader, "include", [])
  let timestamp_granularities = openai_transcription_string_array(
    reader,
    "timestampGranularities",
    ["word", "segment"],
  )
  let timestamp_granularities = if provided &&
    timestamp_granularities.length() == 0 {
    ["segment"]
  } else {
    timestamp_granularities
  }
  let temperature = match reader.take_double("temperature", min=0.0, max=1.0) {
    Some(value) => Some(value)
    None if provided => Some(0.0)
    None => None
  }
  if reader.take_object("streaming") is Some(_) {
    reader.add_warning(
      @provider.Warning::Unsupported(
        feature="providerOptions.openai.streaming",
        details="The current MoonBit TranscriptionModel contract supports buffered transcription only.",
      ),
    )
  }
  {
    options: {
      include_fields,
      language: reader.take_string("language"),
      prompt: reader.take_string("prompt"),
      temperature,
      timestamp_granularities,
      provided,
    },
    warnings: reader.diagnostics(),
  }
}

///|
fn openai_transcription_stream_include(
  reader : @provider_utils.ProviderOptionsReader,
) -> Array[String] {
  let result : Array[String] = []
  match reader.take_array("include") {
    Some(values) =>
      for value in values {
        match value {
          String(text) => result.push(text)
          _ =>
            reader.add_warning(
              @provider.Warning::Compatibility(
                feature="providerOptions.openai.streaming.include",
                details="Expected an array of strings; an invalid item was ignored.",
              ),
            )
        }
      }
    None => ()
  }
  result
}

///|
fn parse_openai_transcription_stream_options(
  provider_options : Map[String, Json],
  _provider_name : String,
) -> ParsedOpenAITranscriptionStreamOptions {
  let resolution = resolve_official_openai_provider_options(provider_options)
  let reader = @provider_utils.ProviderOptionsReader::new(
    resolution,
    path="providerOptions.openai",
  )
  let warnings : Array[@provider.Warning] = []
  for field in ["include", "prompt", "temperature", "timestampGranularities"] {
    if reader.take_json(field) is Some(_) {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="providerOptions.openai.\{field}",
          details="OpenAI streaming transcription does not support \{field}.",
        ),
      )
    }
  }
  let language = reader.take_string("language")
  let mut delay : String? = None
  let include_values : Array[String] = []
  match reader.take_object("streaming") {
    Some(values) => {
      let nested_resolution : @provider_utils.ProviderOptionsResolution = {
        values,
        warnings: [],
        namespace_key: Some("streaming"),
      }
      let nested = @provider_utils.ProviderOptionsReader::new(
        nested_resolution,
        path="providerOptions.openai.streaming",
      )
      delay = nested.take_string("delay", allowed=[
        "minimal", "low", "medium", "high", "xhigh",
      ])
      for value in openai_transcription_stream_include(nested) {
        include_values.push(value)
      }
      for warning in nested.diagnostics() {
        warnings.push(warning)
      }
    }
    None => ()
  }
  for warning in reader.diagnostics() {
    warnings.push(warning)
  }
  { language, delay, include_values, warnings }
}

///|
fn openai_realtime_transcription_session(
  model_id : String,
  audio_format : @provider.AudioFormat,
  options : ParsedOpenAITranscriptionStreamOptions,
) -> Json {
  let format : Map[String, Json] = Map([
    ("type", Json::string(audio_format.media_type)),
  ])
  if audio_format.sample_rate is Some(value) {
    format["rate"] = Json::number(value.to_double())
  }
  let transcription : Map[String, Json] = Map([
    ("model", Json::string(model_id)),
  ])
  if options.language is Some(value) {
    transcription["language"] = Json::string(value)
  }
  if options.delay is Some(value) {
    transcription["delay"] = Json::string(value)
  }
  let session : Map[String, Json] = Map([
    ("type", Json::string("transcription")),
    (
      "audio",
      {
        "input": {
          "format": Json::object(format),
          "transcription": Json::object(transcription),
          "turn_detection": Json::null(),
        },
      },
    ),
  ])
  if options.include_values.length() > 0 {
    session["include"] = Json::array(
      [
        for value in options.include_values => Json::string(value)
      ],
    )
  }
  { "type": "session.update", "session": Json::object(session) }
}

///|
async fn send_openai_transcription_audio(
  connection : &@provider_utils.WebSocketConnection,
  audio : &@provider.AudioStream,
  cancellation_token : @provider.CancellationToken?,
) -> Unit {
  for ;; {
    @provider.check_cancellation(cancellation_token)
    match audio.read_next() {
      Some(chunk) => {
        let encoded = match chunk {
          @provider.AudioBytes(data) =>
            @provider_utils.convert_bytes_to_base64(data)
          @provider.AudioBase64(data) => data
        }
        connection.send_text(
          ({ "type": "input_audio_buffer.append", "audio": encoded } : Json).stringify(),
        )
      }
      None => break
    }
  }
  @provider.check_cancellation(cancellation_token)
  connection.send_text(
    ({ "type": "input_audio_buffer.commit" } : Json).stringify(),
  )
}

///|
fn openai_transcription_close_error(code : Int?, reason : String?) -> String {
  let code_text = match code {
    Some(value) => value.to_string()
    None => "unknown"
  }
  let reason_text = match reason {
    Some(value) if value != "" => ", reason: \{value}"
    _ => ""
  }
  "OpenAI realtime transcription WebSocket closed unexpectedly before finishing (code \{code_text}\{reason_text})."
}

///|
fn append_openai_transcription_text(
  fields : Array[@provider_utils.MultipartField],
  name : String,
  value : String?,
) -> Unit {
  if value is Some(item) {
    fields.push(@provider_utils.MultipartField::text(name~, value=item))
  }
}

///|
fn OpenAITranscriptionModel::form_data(
  self : OpenAITranscriptionModel,
  call_options : @provider.TranscriptionModelV4CallOptions,
  parsed : ParsedOpenAITranscriptionOptions,
) -> @provider_utils.MultipartFormData raise {
  let extension = @provider_utils.media_type_to_extension(
    call_options.media_type,
  )
  let filename = if extension == "" { "audio" } else { "audio.\{extension}" }
  let fields : Array[@provider_utils.MultipartField] = [
    @provider_utils.MultipartField::text(name="model", value=self.model_id),
    @provider_utils.MultipartField::file(
      name="file",
      filename~,
      media_type=call_options.media_type,
      data=@provider_utils.resolve_transcription_audio(call_options.audio),
    ),
  ]
  if self.model_id == "whisper-1" {
    fields.push(
      @provider_utils.MultipartField::text(
        name="response_format",
        value="verbose_json",
      ),
    )
  } else if parsed.options.provided {
    let response_format = if self.model_id == "gpt-4o-transcribe" ||
      self.model_id == "gpt-4o-mini-transcribe" {
      "json"
    } else {
      "verbose_json"
    }
    fields.push(
      @provider_utils.MultipartField::text(
        name="response_format",
        value=response_format,
      ),
    )
  }
  for value in parsed.options.include_fields {
    fields.push(@provider_utils.MultipartField::text(name="include[]", value~))
  }
  append_openai_transcription_text(fields, "language", parsed.options.language)
  append_openai_transcription_text(fields, "prompt", parsed.options.prompt)
  if parsed.options.temperature is Some(value) {
    fields.push(
      @provider_utils.MultipartField::text(
        name="temperature",
        value=value.to_string(),
      ),
    )
  }
  for value in parsed.options.timestamp_granularities {
    fields.push(
      @provider_utils.MultipartField::text(
        name="timestamp_granularities[]",
        value~,
      ),
    )
  }
  @provider_utils.encode_multipart_form_data(fields)
}

///|
fn openai_transcription_segments(
  json : Json,
) -> Array[@provider.TranscriptionSegment] {
  let result : Array[@provider.TranscriptionSegment] = []
  let values = match json {
    { "segments": Array(values), .. } => Some((values, true))
    { "words": Array(values), .. } => Some((values, false))
    _ => None
  }
  match values {
    Some((items, true)) =>
      for item in items {
        match item {
          {
            "text": String(text),
            "start": Number(start, ..),
            "end": Number(end, ..),
            ..
          } =>
            result.push(
              @provider.TranscriptionSegment::new(
                text~,
                start_second=start,
                end_second=end,
              ),
            )
          _ => ()
        }
      }
    Some((items, false)) =>
      for item in items {
        match item {
          {
            "word": String(text),
            "start": Number(start, ..),
            "end": Number(end, ..),
            ..
          } =>
            result.push(
              @provider.TranscriptionSegment::new(
                text~,
                start_second=start,
                end_second=end,
              ),
            )
          _ => ()
        }
      }
    None => ()
  }
  result
}

///|
fn openai_transcription_language(value : String) -> String? {
  match value.to_lower() {
    "afrikaans" => Some("af")
    "arabic" => Some("ar")
    "armenian" => Some("hy")
    "azerbaijani" => Some("az")
    "belarusian" => Some("be")
    "bosnian" => Some("bs")
    "bulgarian" => Some("bg")
    "catalan" => Some("ca")
    "chinese" => Some("zh")
    "croatian" => Some("hr")
    "czech" => Some("cs")
    "danish" => Some("da")
    "dutch" => Some("nl")
    "english" => Some("en")
    "estonian" => Some("et")
    "finnish" => Some("fi")
    "french" => Some("fr")
    "galician" => Some("gl")
    "german" => Some("de")
    "greek" => Some("el")
    "hebrew" => Some("he")
    "hindi" => Some("hi")
    "hungarian" => Some("hu")
    "icelandic" => Some("is")
    "indonesian" => Some("id")
    "italian" => Some("it")
    "japanese" => Some("ja")
    "kannada" => Some("kn")
    "kazakh" => Some("kk")
    "korean" => Some("ko")
    "latvian" => Some("lv")
    "lithuanian" => Some("lt")
    "macedonian" => Some("mk")
    "malay" => Some("ms")
    "marathi" => Some("mr")
    "maori" => Some("mi")
    "nepali" => Some("ne")
    "norwegian" => Some("no")
    "persian" => Some("fa")
    "polish" => Some("pl")
    "portuguese" => Some("pt")
    "romanian" => Some("ro")
    "russian" => Some("ru")
    "serbian" => Some("sr")
    "slovak" => Some("sk")
    "slovenian" => Some("sl")
    "spanish" => Some("es")
    "swahili" => Some("sw")
    "swedish" => Some("sv")
    "tagalog" => Some("tl")
    "tamil" => Some("ta")
    "thai" => Some("th")
    "turkish" => Some("tr")
    "ukrainian" => Some("uk")
    "urdu" => Some("ur")
    "vietnamese" => Some("vi")
    "welsh" => Some("cy")
    _ => None
  }
}

///|
fn decode_openai_transcription_response(
  json : Json,
  model_id : String,
  provider_name : String,
  request_created_at : Int,
  warnings : Array[@provider.Warning],
) -> @provider.TranscriptionModelV4Result raise {
  if openai_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI Transcription request failed: \{message}",
      data=json,
    )
  }
  let text = match json {
    { "text": String(value), .. } => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI Transcription response has no text",
        data=json,
      )
  }
  let language = match json {
    { "language": String(value), .. } => openai_transcription_language(value)
    _ => None
  }
  let duration_seconds = match json {
    { "duration": Number(value, ..), .. } => Some(value)
    _ => None
  }
  let json_metadata = @provider_utils.create_language_model_response_metadata(
    id?=@provider_utils.json_string_field(json, "id"),
    model?=@provider_utils.json_string_field(json, "model"),
    created?=@provider_utils.json_int_field_opt(json, "created"),
  )
  let response_metadata = @provider.merge_response_metadata(
    Some(json_metadata),
    @provider.ResponseMetadata::new(model_id~, created_at=request_created_at),
  )
  @provider.TranscriptionModelV4Result::new(
    text~,
    segments=openai_transcription_segments(json),
    language?,
    duration_in_seconds?=duration_seconds,
    response=response_metadata,
    provider_metadata=@provider_utils.provider_metadata_from_json(
      json, provider_name,
    ),
    warnings~,
  )
}

///|
async fn OpenAITranscriptionModel::transcribe_audio_v4(
  self : OpenAITranscriptionModel,
  call_options : @provider.TranscriptionModelV4CallOptions,
) -> @provider.TranscriptionModelV4Result {
  let request_created_at = (@env.now() / 1000UL).to_int()
  if openai_is_realtime_transcription_model(self.model_id) {
    raise @provider.UnsupportedFunctionalityError(
      functionality="non-streaming transcription with \{self.model_id}",
    )
  }
  let parsed = parse_openai_transcription_options(
    call_options.provider_options,
    self.provider_name,
  )
  let cancellation_token = call_options.cancellation_token
  let response = @provider_utils.post_multipart(
    provider_name=self.provider_name,
    url=self.url(),
    headers=self.request_headers(call_options.headers),
    form_data=self.form_data(call_options, parsed),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=call_options.retry_policy,
    cancellation_token?,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  let decoded = @provider_utils.handle_json_response(response, value => {
    decode_openai_transcription_response(
      value,
      self.model_id,
      self.provider_name,
      request_created_at,
      parsed.warnings,
    )
  })
  @provider.TranscriptionModelV4Result::new(
    text=decoded.text,
    segments=decoded.segments,
    language?=decoded.language,
    duration_in_seconds?=decoded.duration_in_seconds,
    warnings=decoded.warnings,
    request=response.request,
    response=@provider.merge_response_metadata(
      decoded.response,
      response.response,
    ),
    provider_metadata=decoded.provider_metadata,
  )
}

///|
async fn OpenAITranscriptionModel::stream_transcription_v4(
  self : OpenAITranscriptionModel,
  call_options : @provider.TranscriptionModelV4StreamOptions,
  on_event : async (@provider.TranscriptionModelV4StreamPart) -> Unit,
) -> @provider.TranscriptionModelV4Result {
  let request_created_at = (@env.now() / 1000UL).to_int()
  guard openai_is_realtime_transcription_model(self.model_id) else {
    raise @provider.UnsupportedFunctionalityError(
      functionality="streaming transcription with \{self.model_id}",
    )
  }
  @provider.check_cancellation(call_options.cancellation_token)
  let parsed = parse_openai_transcription_stream_options(
    call_options.provider_options,
    self.provider_name,
  )
  let session_update = openai_realtime_transcription_session(
    self.model_id,
    call_options.input_audio_format,
    parsed,
  )
  let url = @provider_utils.to_websocket_url(
    @provider_utils.append_query(
      @provider_utils.append_path(self.base_url, "/realtime"),
      { "intent": "transcription" },
    ),
  )
  let realtime = openai_realtime_connection_options(
    self.stream_request_headers(call_options.headers),
  )
  defer call_options.audio.cancel()
  let connection = self.websocket_connector.connect(
    url,
    realtime.protocols,
    realtime.headers,
  )
  defer connection.close()
  on_event(@provider.TranscriptionV4StreamStart(warnings=parsed.warnings))
  connection.send_text(session_update.stringify())
  let mut final_text = ""
  let mut final_id : String? = None
  @async.with_task_group() <| group => {
    let sender = group.spawn(no_wait=true) <| () => {
      send_openai_transcription_audio(
        connection,
        call_options.audio,
        call_options.cancellation_token,
      )
    }
    defer sender.cancel()
    match call_options.cancellation_token {
      Some(token) =>
        group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
          while !token.is_cancelled() {
            @async.sleep(20)
          }
          connection.close()
        }
      None => ()
    }
    let mut finished = false
    while !finished {
      let received = connection.receive()
      let text = match received {
        @provider_utils.WebSocketText(value) => value
        @provider_utils.WebSocketBinary(value) => @utf8.decode(value)
        @provider_utils.WebSocketClosed(code~, reason~) => {
          @provider.check_cancellation(call_options.cancellation_token)
          fail(openai_transcription_close_error(code, reason))
        }
      }
      let raw : Json? = Some(@json.parse(text)) catch { _ => None }
      match raw {
        None => ()
        Some(event) => {
          if call_options.include_raw_chunks {
            on_event(@provider.TranscriptionV4Raw(event))
          }
          match @provider_utils.json_string_field(event, "type") {
            Some("conversation.item.input_audio_transcription.delta") => {
              let delta = @provider_utils.json_string_field(event, "delta").unwrap_or(
                "",
              )
              on_event(
                @provider.TranscriptionV4TranscriptDelta(
                  id=@provider_utils.json_string_field(event, "item_id"),
                  delta~,
                  provider_metadata=Map([]),
                ),
              )
            }
            Some("conversation.item.input_audio_transcription.completed") => {
              final_text = @provider_utils.json_string_field(
                event, "transcript",
              ).unwrap_or("")
              final_id = @provider_utils.json_string_field(event, "item_id")
              finished = true
            }
            Some("error") => {
              let message = openai_error_message(event).unwrap_or(
                "OpenAI realtime error",
              )
              on_event(
                @provider.TranscriptionV4Error(
                  @provider.StreamErrorInfo::new(message, data=event),
                ),
              )
              fail(message)
            }
            _ => ()
          }
        }
      }
    }
  }
  connection.send_close(1000, None)
  if final_id is Some(id) {
    on_event(
      @provider.TranscriptionV4TranscriptFinal(
        id=Some(id),
        text=final_text,
        start_second=None,
        end_second=None,
        channel_index=None,
        provider_metadata=Map([]),
      ),
    )
  }
  on_event(
    @provider.TranscriptionV4Finish(
      text=final_text,
      segments=[],
      language=parsed.language,
      duration_in_seconds=None,
      provider_metadata=Map([]),
    ),
  )
  @provider.TranscriptionModelV4Result::new(
    text=final_text,
    language?=parsed.language,
    request=@provider.RequestMetadata::new(
      url~,
      headers=realtime.headers,
      body=session_update.stringify(),
    ),
    response=@provider.ResponseMetadata::new(
      model_id=self.model_id,
      created_at=request_created_at,
    ),
    warnings=parsed.warnings,
  )
}

///|
impl @provider.TranscriptionModelV4 for OpenAITranscriptionModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.TranscriptionModelV4 for OpenAITranscriptionModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
impl @provider.TranscriptionModelV4 for OpenAITranscriptionModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
impl @provider.TranscriptionModelV4 for OpenAITranscriptionModel with fn do_generate(
  self,
  options,
) {
  self.transcribe_audio_v4(options)
}

///|
impl @provider.TranscriptionModelV4 for OpenAITranscriptionModel with fn do_stream(
  self,
  options,
  on_part,
) {
  let response = self.stream_transcription_v4(options, on_part)
  @provider.TranscriptionModelV4StreamResult::new(
    request?=response.request,
    response?=response.response,
  )
}
