///|
/// First client text frame in the shared transcription WebSocket envelope.
pub const TRANSCRIPTION_STREAM_START_FRAME_TYPE : String = "transcription-stream.start"

///|
/// Client text frame that marks the end of binary audio input.
pub const TRANSCRIPTION_STREAM_AUDIO_DONE_FRAME_TYPE : String = "transcription-stream.audio-done"

///|
/// Session metadata carried by the first client frame of a shared
/// transcription WebSocket stream.
pub(all) struct TranscriptionStreamStartFrame {
  input_audio_format : @provider.AudioFormat
  provider_options : Map[String, Json]?
  include_raw_chunks : Bool?
} derive(Debug, Eq)

///|
/// Construct a transcription stream start frame.
pub fn TranscriptionStreamStartFrame::new(
  input_audio_format~ : @provider.AudioFormat,
  provider_options? : Map[String, Json],
  include_raw_chunks? : Bool,
) -> TranscriptionStreamStartFrame {
  { input_audio_format, provider_options, include_raw_chunks }
}

///|
/// Classification of one client text frame in the shared envelope.
pub(all) enum TranscriptionStreamClientFrame {
  TranscriptionStreamStart(TranscriptionStreamStartFrame)
  TranscriptionStreamAudioDone
  TranscriptionStreamInvalid(String)
  TranscriptionStreamUnknown
} derive(Debug, Eq)

///|
fn envelope_copy_json_map(source : Map[String, Json]) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for entry in source.iter2() {
    let (key, value) = entry
    result[key] = value
  }
  result
}

///|
fn envelope_json_is_unsafe(value : Json) -> Bool {
  match value {
    Object(fields) => {
      for entry in fields.iter2() {
        let (key, item) = entry
        if key == "__proto__" {
          return true
        }
        if key == "constructor" {
          match item {
            Object(constructor_value) if constructor_value.get("prototype")
              is Some(_) => return true
            _ => ()
          }
        }
        if envelope_json_is_unsafe(item) {
          return true
        }
      }
      false
    }
    Array(items) => items.any(envelope_json_is_unsafe)
    _ => false
  }
}

///|
fn parse_envelope_json(text : String) -> Json? {
  let parsed : Json? = Some(@json.parse(text)) catch { _ => None }
  match parsed {
    Some(value) if !envelope_json_is_unsafe(value) => Some(value)
    _ => None
  }
}

///|
fn json_object_values_are_objects(fields : Map[String, Json]) -> Bool {
  for entry in fields.iter2() {
    let (_, value) = entry
    guard value is Object(_) else { return false }
  }
  true
}

///|
/// Serialize a shared transcription start frame as one WebSocket text frame.
pub fn serialize_transcription_stream_start_frame(
  frame : TranscriptionStreamStartFrame,
) -> String {
  let format : Map[String, Json] = Map([
    ("type", Json::string(frame.input_audio_format.media_type)),
  ])
  if frame.input_audio_format.sample_rate is Some(rate) {
    format["rate"] = Json::number(rate.to_double())
  }
  let fields : Map[String, Json] = Map([
    ("type", Json::string(TRANSCRIPTION_STREAM_START_FRAME_TYPE)),
    ("inputAudioFormat", Json::object(format)),
  ])
  if frame.provider_options is Some(options) {
    fields["providerOptions"] = Json::object(envelope_copy_json_map(options))
  }
  if frame.include_raw_chunks is Some(value) {
    fields["includeRawChunks"] = Json::boolean(value)
  }
  Json::object(fields).stringify()
}

///|
/// AI SDK-style camel-case spelling.
pub fn serializeTranscriptionStreamStartFrame(
  frame : TranscriptionStreamStartFrame,
) -> String {
  serialize_transcription_stream_start_frame(frame)
}

///|
/// Serialize the client frame that marks the end of audio input.
pub fn serialize_transcription_stream_audio_done_frame() -> String {
  ({ "type": TRANSCRIPTION_STREAM_AUDIO_DONE_FRAME_TYPE } : Json).stringify()
}

///|
/// AI SDK-style camel-case spelling.
pub fn serializeTranscriptionStreamAudioDoneFrame() -> String {
  serialize_transcription_stream_audio_done_frame()
}

///|
/// Parse and validate one client text frame. Unknown frame types are retained
/// as a forward-compatible classification; malformed recognized frames never
/// escape as partially valid data.
pub fn parse_transcription_stream_client_frame(
  text : String,
) -> TranscriptionStreamClientFrame {
  let value = match parse_envelope_json(text) {
    Some(value) => value
    None => return TranscriptionStreamInvalid("malformed JSON")
  }
  let fields = match value {
    Object(fields) => fields
    _ => return TranscriptionStreamInvalid("frame must be a JSON object")
  }
  let frame_type = match fields.get("type") {
    Some(String(value)) => value
    _ => return TranscriptionStreamInvalid("frame type must be a string")
  }
  if frame_type == TRANSCRIPTION_STREAM_AUDIO_DONE_FRAME_TYPE {
    return TranscriptionStreamAudioDone
  }
  if frame_type != TRANSCRIPTION_STREAM_START_FRAME_TYPE {
    return TranscriptionStreamUnknown
  }
  let format = match fields.get("inputAudioFormat") {
    Some(Object(value)) => value
    _ =>
      return TranscriptionStreamInvalid(
        "start frame must have an inputAudioFormat object with a string type",
      )
  }
  let media_type = match format.get("type") {
    Some(String(value)) => value
    _ =>
      return TranscriptionStreamInvalid(
        "start frame must have an inputAudioFormat object with a string type",
      )
  }
  let sample_rate = match format.get("rate") {
    None => None
    Some(Number(value, ..)) if value == value.to_int().to_double() =>
      Some(value.to_int())
    _ =>
      return TranscriptionStreamInvalid(
        "inputAudioFormat.rate must be a number when present",
      )
  }
  let provider_options = match fields.get("providerOptions") {
    None => None
    Some(Object(options)) if json_object_values_are_objects(options) =>
      Some(envelope_copy_json_map(options))
    _ =>
      return TranscriptionStreamInvalid(
        "providerOptions must be an object when present",
      )
  }
  let include_raw_chunks = match fields.get("includeRawChunks") {
    None => None
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ =>
      return TranscriptionStreamInvalid(
        "includeRawChunks must be a boolean when present",
      )
  }
  TranscriptionStreamStart(
    TranscriptionStreamStartFrame::new(
      input_audio_format=@provider.AudioFormat::new(media_type~, sample_rate?),
      provider_options?,
      include_raw_chunks?,
    ),
  )
}

///|
/// AI SDK-style camel-case spelling.
pub fn parseTranscriptionStreamClientFrame(
  text : String,
) -> TranscriptionStreamClientFrame {
  parse_transcription_stream_client_frame(text)
}

///|
fn warning_to_envelope_json(warning : @provider.Warning) -> Json {
  match warning {
    @provider.Unsupported(feature~, details~) =>
      { "type": "unsupported", "feature": feature, "details": details }
    @provider.Compatibility(feature~, details~) =>
      { "type": "compatibility", "feature": feature, "details": details }
    @provider.Deprecated(setting~, message~) =>
      { "type": "deprecated", "setting": setting, "message": message }
    @provider.Other(message~) => { "type": "other", "message": message }
  }
}

///|
fn warning_from_envelope_json(value : Json) -> @provider.Warning? {
  let fields = match value {
    Object(fields) => fields
    _ => return None
  }
  let warning_type = match fields.get("type") {
    Some(String(value)) => value
    _ => return None
  }
  match warning_type {
    "unsupported" =>
      Some(
        @provider.Unsupported(
          feature=match fields.get("feature") {
            Some(String(value)) => value
            _ => ""
          },
          details=match fields.get("details") {
            Some(String(value)) => value
            _ => ""
          },
        ),
      )
    "compatibility" =>
      Some(
        @provider.Compatibility(
          feature=match fields.get("feature") {
            Some(String(value)) => value
            _ => ""
          },
          details=match fields.get("details") {
            Some(String(value)) => value
            _ => ""
          },
        ),
      )
    "deprecated" =>
      Some(
        @provider.Deprecated(
          setting=match fields.get("setting") {
            Some(String(value)) => value
            _ => ""
          },
          message=match fields.get("message") {
            Some(String(value)) => value
            _ => ""
          },
        ),
      )
    "other" =>
      Some(
        @provider.Other(
          message=match fields.get("message") {
            Some(String(value)) => value
            _ => ""
          },
        ),
      )
    _ => Some(@provider.Other(message=value.stringify()))
  }
}

///|
fn provider_metadata_to_envelope_json(metadata : Map[String, Json]) -> Json {
  Json::object(envelope_copy_json_map(metadata))
}

///|
fn string_headers_to_json(headers : Map[String, String]) -> Json {
  let fields : Map[String, Json] = Map([])
  for entry in headers.iter2() {
    let (key, value) = entry
    fields[key] = Json::string(value)
  }
  Json::object(fields)
}

///|
fn envelope_pad_two(value : Int) -> String {
  if value < 10 {
    "0\{value}"
  } else {
    value.to_string()
  }
}

///|
fn envelope_pad_four(value : Int) -> String {
  if value < 10 {
    "000\{value}"
  } else if value < 100 {
    "00\{value}"
  } else if value < 1000 {
    "0\{value}"
  } else {
    value.to_string()
  }
}

///|
fn envelope_civil_from_days(days_since_epoch : Int) -> (Int, Int, Int) {
  let z = days_since_epoch + 719468
  let era = z / 146097
  let day_of_era = z - era * 146097
  let year_of_era = (
      day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096
    ) /
    365
  let mut year = year_of_era + era * 400
  let day_of_year = day_of_era -
    (365 * year_of_era + year_of_era / 4 - year_of_era / 100)
  let month_prime = (5 * day_of_year + 2) / 153
  let day = day_of_year - (153 * month_prime + 2) / 5 + 1
  let month = month_prime + (if month_prime < 10 { 3 } else { -9 })
  if month <= 2 {
    year = year + 1
  }
  (year, month, day)
}

///|
fn envelope_timestamp_to_iso(created_at : Int) -> String? {
  guard created_at >= 0 else { return None }
  let days = created_at / 86400
  let seconds_in_day = created_at % 86400
  let (year, month, day) = envelope_civil_from_days(days)
  guard year >= 0 && year <= 9999 else { return None }
  let hour = seconds_in_day / 3600
  let minute = seconds_in_day % 3600 / 60
  let second = seconds_in_day % 60
  Some(
    "\{envelope_pad_four(year)}-\{envelope_pad_two(month)}-\{envelope_pad_two(day)}T\{envelope_pad_two(hour)}:\{envelope_pad_two(minute)}:\{envelope_pad_two(second)}.000Z",
  )
}

///|
fn parse_envelope_decimal(value : String) -> Int? {
  try @string.parse_int(value) catch {
    _ => None
  } noraise {
    number => Some(number)
  }
}

///|
fn envelope_is_leap_year(year : Int) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
fn envelope_days_in_month(year : Int, month : Int) -> Int {
  match month {
    2 => if envelope_is_leap_year(year) { 29 } else { 28 }
    4 | 6 | 9 | 11 => 30
    _ => 31
  }
}

///|
fn envelope_days_from_civil(year : Int, month : Int, day : Int) -> Int {
  let adjusted_year = year - (if month <= 2 { 1 } else { 0 })
  let era = adjusted_year / 400
  let year_of_era = adjusted_year - era * 400
  let month_prime = month + (if month > 2 { -3 } else { 9 })
  let day_of_year = (153 * month_prime + 2) / 5 + day - 1
  let day_of_era = year_of_era * 365 +
    year_of_era / 4 -
    year_of_era / 100 +
    day_of_year
  era * 146097 + day_of_era - 719468
}

///|
fn envelope_iso_to_timestamp(value : String) -> Int? {
  guard value.length() >= 20 && value.has_suffix("Z") else { return None }
  guard value[4:5].to_owned() == "-" &&
    value[7:8].to_owned() == "-" &&
    value[10:11].to_owned() == "T" &&
    value[13:14].to_owned() == ":" &&
    value[16:17].to_owned() == ":" else {
    return None
  }
  if value.length() > 20 {
    guard value[19:20].to_owned() == "." else { return None }
    for byte in @utf8.encode(value[20:value.length() - 1].to_owned()) {
      guard byte >= b'0' && byte <= b'9' else { return None }
    }
  }
  let year = match parse_envelope_decimal(value[:4].to_owned()) {
    Some(value) => value
    None => return None
  }
  let month = match parse_envelope_decimal(value[5:7].to_owned()) {
    Some(value) => value
    None => return None
  }
  let day = match parse_envelope_decimal(value[8:10].to_owned()) {
    Some(value) => value
    None => return None
  }
  let hour = match parse_envelope_decimal(value[11:13].to_owned()) {
    Some(value) => value
    None => return None
  }
  let minute = match parse_envelope_decimal(value[14:16].to_owned()) {
    Some(value) => value
    None => return None
  }
  let second = match parse_envelope_decimal(value[17:19].to_owned()) {
    Some(value) => value
    None => return None
  }
  guard year >= 1970 &&
    month >= 1 &&
    month <= 12 &&
    day >= 1 &&
    day <= envelope_days_in_month(year, month) &&
    hour >= 0 &&
    hour <= 23 &&
    minute >= 0 &&
    minute <= 59 &&
    second >= 0 &&
    second <= 59 else {
    return None
  }
  let days = envelope_days_from_civil(year, month, day)
  guard days >= 0 && days <= 24855 else { return None }
  let timestamp = days * 86400 + hour * 3600 + minute * 60 + second
  guard timestamp >= 0 else { return None }
  Some(timestamp)
}

///|
fn put_optional_string(
  fields : Map[String, Json],
  name : String,
  value : String?,
) -> Unit {
  if value is Some(item) {
    fields[name] = Json::string(item)
  }
}

///|
fn put_optional_double(
  fields : Map[String, Json],
  name : String,
  value : Double?,
) -> Unit {
  if value is Some(item) {
    fields[name] = Json::number(item)
  }
}

///|
fn put_optional_int(
  fields : Map[String, Json],
  name : String,
  value : Int?,
) -> Unit {
  if value is Some(item) {
    fields[name] = Json::number(item.to_double())
  }
}

///|
fn put_provider_metadata(
  fields : Map[String, Json],
  metadata : Map[String, Json],
) -> Unit {
  if metadata.length() > 0 {
    fields["providerMetadata"] = provider_metadata_to_envelope_json(metadata)
  }
}

///|
fn transcription_stream_part_to_json(
  part : @provider.TranscriptionModelV4StreamPart,
) -> Json {
  match part {
    @provider.TranscriptionV4StreamStart(warnings~) =>
      {
        "type": "stream-start",
        "warnings": [
          for warning in warnings => warning_to_envelope_json(warning)
        ],
      }
    @provider.TranscriptionV4TranscriptDelta(id~, delta~, provider_metadata~) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("transcript-delta")),
        ("delta", Json::string(delta)),
      ])
      put_optional_string(fields, "id", id)
      put_provider_metadata(fields, provider_metadata)
      Json::object(fields)
    }
    @provider.TranscriptionV4TranscriptPartial(
      id~,
      text~,
      start_second~,
      duration_in_seconds~,
      channel_index~,
      provider_metadata~
    ) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("transcript-partial")),
        ("text", Json::string(text)),
      ])
      put_optional_string(fields, "id", id)
      put_optional_double(fields, "startSecond", start_second)
      put_optional_double(fields, "durationInSeconds", duration_in_seconds)
      put_optional_int(fields, "channelIndex", channel_index)
      put_provider_metadata(fields, provider_metadata)
      Json::object(fields)
    }
    @provider.TranscriptionV4TranscriptFinal(
      id~,
      text~,
      start_second~,
      end_second~,
      channel_index~,
      provider_metadata~
    ) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("transcript-final")),
        ("text", Json::string(text)),
      ])
      put_optional_string(fields, "id", id)
      put_optional_double(fields, "startSecond", start_second)
      put_optional_double(fields, "endSecond", end_second)
      put_optional_int(fields, "channelIndex", channel_index)
      put_provider_metadata(fields, provider_metadata)
      Json::object(fields)
    }
    @provider.TranscriptionV4ResponseMetadata(metadata) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("response-metadata")),
      ])
      put_optional_string(fields, "modelId", metadata.model_id)
      if metadata.created_at is Some(created_at) &&
        envelope_timestamp_to_iso(created_at) is Some(timestamp) {
        fields["timestamp"] = Json::string(timestamp)
      }
      if metadata.headers.length() > 0 {
        fields["headers"] = string_headers_to_json(metadata.headers)
      }
      put_optional_string(fields, "body", metadata.body)
      Json::object(fields)
    }
    @provider.TranscriptionV4Finish(
      text~,
      segments~,
      language~,
      duration_in_seconds~,
      provider_metadata~
    ) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("finish")),
        ("text", Json::string(text)),
        (
          "segments",
          Json::array(
            [
              for segment in segments => {
                {
                  "text": segment.text,
                  "startSecond": segment.start_second,
                  "endSecond": segment.end_second,
                }
              }
            ],
          ),
        ),
      ])
      put_optional_string(fields, "language", language)
      put_optional_double(fields, "durationInSeconds", duration_in_seconds)
      put_provider_metadata(fields, provider_metadata)
      Json::object(fields)
    }
    @provider.TranscriptionV4Raw(value) => { "type": "raw", "rawValue": value }
    @provider.TranscriptionV4Error(error) => {
      let error_value = match error.data {
        Some(data) => ({ "message": error.message, "data": data } : Json)
        None => Json::string(error.message)
      }
      { "type": "error", "error": error_value }
    }
  }
}

///|
/// Serialize one V4 transcription stream part as a flattened WebSocket text
/// frame. MoonBit stream parts contain only JSON-safe values, so serialization
/// cannot encounter JavaScript's bigint or cyclic-object failures.
pub fn serialize_transcription_stream_part(
  part : @provider.TranscriptionModelV4StreamPart,
) -> String? {
  Some(transcription_stream_part_to_json(part).stringify())
}

///|
/// AI SDK-style camel-case spelling.
pub fn serializeTranscriptionStreamPart(
  part : @provider.TranscriptionModelV4StreamPart,
) -> String? {
  serialize_transcription_stream_part(part)
}

///|
fn optional_string_field(
  fields : Map[String, Json],
  name : String,
) -> (Bool, String?) {
  match fields.get(name) {
    None => (true, None)
    Some(String(value)) => (true, Some(value))
    _ => (false, None)
  }
}

///|
fn optional_double_field(
  fields : Map[String, Json],
  name : String,
) -> (Bool, Double?) {
  match fields.get(name) {
    None => (true, None)
    Some(Number(value, ..)) => (true, Some(value))
    _ => (false, None)
  }
}

///|
fn optional_int_field(
  fields : Map[String, Json],
  name : String,
) -> (Bool, Int?) {
  match fields.get(name) {
    None => (true, None)
    Some(Number(value, ..)) if value == value.to_int().to_double() =>
      (true, Some(value.to_int()))
    _ => (false, None)
  }
}

///|
fn optional_provider_metadata_field(
  fields : Map[String, Json],
) -> (Bool, Map[String, Json]) {
  match fields.get("providerMetadata") {
    None => (true, Map([]))
    Some(Object(metadata)) => (true, envelope_copy_json_map(metadata))
    _ => (false, Map([]))
  }
}

///|
fn parse_envelope_headers(value : Json) -> Map[String, String]? {
  let fields = match value {
    Object(fields) => fields
    _ => return None
  }
  let headers : Map[String, String] = Map([])
  for entry in fields.iter2() {
    let (key, item) = entry
    match item {
      String(value) => headers[key] = value
      _ => return None
    }
  }
  Some(headers)
}

///|
fn parse_envelope_segments(
  value : Json,
) -> Array[@provider.TranscriptionSegment]? {
  let items = match value {
    Array(items) => items
    _ => return None
  }
  let segments : Array[@provider.TranscriptionSegment] = []
  for item in items {
    let fields = match item {
      Object(fields) => fields
      _ => return None
    }
    let text = match fields.get("text") {
      Some(String(value)) => value
      _ => return None
    }
    let start_second = match fields.get("startSecond") {
      Some(Number(value, ..)) => value
      _ => return None
    }
    let end_second = match fields.get("endSecond") {
      Some(Number(value, ..)) => value
      _ => return None
    }
    segments.push(
      @provider.TranscriptionSegment::new(text~, start_second~, end_second~),
    )
  }
  Some(segments)
}

///|
fn parse_transcription_error(value : Json) -> @provider.StreamErrorInfo {
  match value {
    String(message) => @provider.StreamErrorInfo::new(message)
    Object(fields) => {
      let message = match fields.get("message") {
        Some(String(value)) => value
        _ => value.stringify()
      }
      match fields.get("data") {
        Some(data) => @provider.StreamErrorInfo::new(message, data~)
        None => @provider.StreamErrorInfo::new(message, data=value)
      }
    }
    _ => @provider.StreamErrorInfo::new(value.stringify(), data=value)
  }
}

///|
/// Parse one server text frame into the normalized V4 transcription
/// vocabulary. Malformed, unsafe, unknown, or shape-incompatible parts are
/// ignored for forward compatibility.
pub fn parse_transcription_stream_part(
  text : String,
) -> @provider.TranscriptionModelV4StreamPart? {
  let value = match parse_envelope_json(text) {
    Some(value) => value
    None => return None
  }
  let fields = match value {
    Object(fields) => fields
    _ => return None
  }
  let part_type = match fields.get("type") {
    Some(String(value)) => value
    _ => return None
  }
  match part_type {
    "stream-start" => {
      let items = match fields.get("warnings") {
        Some(Array(items)) => items
        _ => return None
      }
      let warnings : Array[@provider.Warning] = []
      for item in items {
        match warning_from_envelope_json(item) {
          Some(warning) => warnings.push(warning)
          None => return None
        }
      }
      Some(@provider.TranscriptionV4StreamStart(warnings~))
    }
    "transcript-delta" => {
      let delta = match fields.get("delta") {
        Some(String(value)) => value
        _ => return None
      }
      let (valid_id, id) = optional_string_field(fields, "id")
      let (valid_metadata, provider_metadata) = optional_provider_metadata_field(
        fields,
      )
      guard valid_id && valid_metadata else { return None }
      Some(
        @provider.TranscriptionV4TranscriptDelta(
          id~,
          delta~,
          provider_metadata~,
        ),
      )
    }
    "transcript-partial" => {
      let transcript = match fields.get("text") {
        Some(String(value)) => value
        _ => return None
      }
      let (valid_id, id) = optional_string_field(fields, "id")
      let (valid_start, start_second) = optional_double_field(
        fields, "startSecond",
      )
      let (valid_duration, duration_in_seconds) = optional_double_field(
        fields, "durationInSeconds",
      )
      let (valid_channel, channel_index) = optional_int_field(
        fields, "channelIndex",
      )
      let (valid_metadata, provider_metadata) = optional_provider_metadata_field(
        fields,
      )
      guard valid_id &&
        valid_start &&
        valid_duration &&
        valid_channel &&
        valid_metadata else {
        return None
      }
      Some(
        @provider.TranscriptionV4TranscriptPartial(
          id~,
          text=transcript,
          start_second~,
          duration_in_seconds~,
          channel_index~,
          provider_metadata~,
        ),
      )
    }
    "transcript-final" => {
      let transcript = match fields.get("text") {
        Some(String(value)) => value
        _ => return None
      }
      let (valid_id, id) = optional_string_field(fields, "id")
      let (valid_start, start_second) = optional_double_field(
        fields, "startSecond",
      )
      let (valid_end, end_second) = optional_double_field(fields, "endSecond")
      let (valid_channel, channel_index) = optional_int_field(
        fields, "channelIndex",
      )
      let (valid_metadata, provider_metadata) = optional_provider_metadata_field(
        fields,
      )
      guard valid_id &&
        valid_start &&
        valid_end &&
        valid_channel &&
        valid_metadata else {
        return None
      }
      Some(
        @provider.TranscriptionV4TranscriptFinal(
          id~,
          text=transcript,
          start_second~,
          end_second~,
          channel_index~,
          provider_metadata~,
        ),
      )
    }
    "response-metadata" => {
      let (valid_model, model_id) = optional_string_field(fields, "modelId")
      guard valid_model else { return None }
      let created_at = match fields.get("timestamp") {
        None | Some(Null) => None
        Some(String(timestamp)) =>
          match envelope_iso_to_timestamp(timestamp) {
            Some(value) => Some(value)
            None => return None
          }
        _ => return None
      }
      let headers = match fields.get("headers") {
        None => Map([])
        Some(value) =>
          match parse_envelope_headers(value) {
            Some(headers) => headers
            None => return None
          }
      }
      let body = match fields.get("body") {
        None | Some(Null) => None
        Some(String(value)) => Some(value)
        Some(value) => Some(value.stringify())
      }
      Some(
        @provider.TranscriptionV4ResponseMetadata(
          @provider.ResponseMetadata::new(
            model_id?,
            created_at?,
            headers~,
            body?,
          ),
        ),
      )
    }
    "finish" => {
      let transcript = match fields.get("text") {
        Some(String(value)) => value
        _ => return None
      }
      let segments = match fields.get("segments") {
        Some(value) =>
          match parse_envelope_segments(value) {
            Some(segments) => segments
            None => return None
          }
        None => return None
      }
      let (valid_language, language) = optional_string_field(fields, "language")
      let (valid_duration, duration_in_seconds) = optional_double_field(
        fields, "durationInSeconds",
      )
      let (valid_metadata, provider_metadata) = optional_provider_metadata_field(
        fields,
      )
      guard valid_language && valid_duration && valid_metadata else {
        return None
      }
      Some(
        @provider.TranscriptionV4Finish(
          text=transcript,
          segments~,
          language~,
          duration_in_seconds~,
          provider_metadata~,
        ),
      )
    }
    "raw" =>
      match fields.get("rawValue") {
        Some(value) => Some(@provider.TranscriptionV4Raw(value))
        None => None
      }
    "error" =>
      match fields.get("error") {
        Some(value) =>
          Some(@provider.TranscriptionV4Error(parse_transcription_error(value)))
        None => None
      }
    _ => None
  }
}

///|
/// AI SDK-style camel-case spelling.
pub fn parseTranscriptionStreamPart(
  text : String,
) -> @provider.TranscriptionModelV4StreamPart? {
  parse_transcription_stream_part(text)
}
