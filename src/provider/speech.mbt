///|
/// Audio data returned by a speech provider.
pub(all) enum SpeechAudioData {
  SpeechAudioBytes(Bytes)
  SpeechAudioBase64(String)
} derive(Debug, Eq)

///|
/// Construct binary generated speech data.
pub fn SpeechAudioData::bytes(data : Bytes) -> SpeechAudioData {
  SpeechAudioBytes(data)
}

///|
/// Construct Base64 generated speech data.
pub fn SpeechAudioData::base64(data : String) -> SpeechAudioData {
  SpeechAudioBase64(data)
}

///|
/// Return whether generated speech contains no payload.
pub fn SpeechAudioData::is_empty(self : SpeechAudioData) -> Bool {
  match self {
    SpeechAudioBytes(data) => data.length() == 0
    SpeechAudioBase64(data) => data.is_empty()
  }
}

///|
/// Provider-neutral options for converting text to speech.
pub(all) struct SpeechCallOptions {
  text : String
  voice : String?
  output_format : String?
  instructions : String?
  speed : Double?
  language : String?
  headers : Map[String, String]
  provider_options : Map[String, Json]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct one speech generation call.
pub fn SpeechCallOptions::new(
  text~ : String,
  voice? : String,
  output_format? : String,
  instructions? : String,
  speed? : Double,
  language? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> SpeechCallOptions {
  {
    text,
    voice,
    output_format,
    instructions,
    speed,
    language,
    headers,
    provider_options,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Result returned by a speech model.
pub(all) struct SpeechResponse {
  audio : SpeechAudioData
  media_type : String
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct a speech response without transport diagnostics.
pub fn SpeechResponse::new(
  audio~ : SpeechAudioData,
  media_type~ : String,
) -> SpeechResponse {
  {
    audio,
    media_type,
    request: None,
    response: None,
    provider_metadata: Map([]),
    warnings: [],
  }
}

///|
/// Attach diagnostics to a speech result.
pub fn SpeechResponse::with_diagnostics(
  self : SpeechResponse,
  request : RequestMetadata?,
  response : ResponseMetadata?,
  provider_metadata : Map[String, Json],
  warnings : Array[Warning],
) -> SpeechResponse {
  {
    audio: self.audio,
    media_type: self.media_type,
    request,
    response,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Add HTTP metadata to a speech result.
pub fn SpeechResponse::with_transport(
  self : SpeechResponse,
  request : RequestMetadata,
  response : ResponseMetadata,
) -> SpeechResponse {
  {
    audio: self.audio,
    media_type: self.media_type,
    request: Some(request),
    response: Some(merge_response_metadata(self.response, response)),
    provider_metadata: copy_provider_metadata(self.provider_metadata),
    warnings: copy_warnings(self.warnings),
  }
}
