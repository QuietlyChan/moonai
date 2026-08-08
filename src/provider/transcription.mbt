///|
/// Inline audio accepted by a transcription model.
pub(all) enum TranscriptionAudio {
  TranscriptionAudioBytes(Bytes)
  TranscriptionAudioBase64(String)
} derive(Debug, Eq)

///|
/// Construct raw-byte transcription input.
pub fn TranscriptionAudio::bytes(data : Bytes) -> TranscriptionAudio {
  TranscriptionAudioBytes(data)
}

///|
/// Construct Base64 transcription input.
pub fn TranscriptionAudio::base64(data : String) -> TranscriptionAudio {
  TranscriptionAudioBase64(data)
}

///|
/// One timed transcription segment.
pub(all) struct TranscriptionSegment {
  text : String
  start_second : Double
  end_second : Double
} derive(Debug, Eq)

///|
/// Construct a timed transcription segment.
pub fn TranscriptionSegment::new(
  text~ : String,
  start_second~ : Double,
  end_second~ : Double,
) -> TranscriptionSegment {
  { text, start_second, end_second }
}

///|
/// Provider-neutral options for transcribing one audio payload.
pub(all) struct TranscriptionCallOptions {
  audio : TranscriptionAudio
  media_type : String
  headers : Map[String, String]
  provider_options : Map[String, Json]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct one transcription call.
pub fn TranscriptionCallOptions::new(
  audio~ : TranscriptionAudio,
  media_type~ : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> TranscriptionCallOptions {
  {
    audio,
    media_type,
    headers,
    provider_options,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Provider-neutral options for a live transcription session.
pub struct TranscriptionStreamOptions {
  audio : &AudioStream
  input_audio_format : AudioFormat
  provider_options : Map[String, Json]
  headers : Map[String, String]
  include_raw_chunks : Bool
  cancellation_token : CancellationToken?
}

///|
/// Construct normalized live transcription options.
pub fn TranscriptionStreamOptions::new(
  audio~ : &AudioStream,
  input_audio_format~ : AudioFormat,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  include_raw_chunks? : Bool = false,
  cancellation_token? : CancellationToken,
) -> TranscriptionStreamOptions {
  {
    audio,
    input_audio_format,
    provider_options,
    headers,
    include_raw_chunks,
    cancellation_token,
  }
}

///|
/// Provider-neutral events emitted during live transcription.
pub(all) enum TranscriptionStreamEvent {
  TranscriptionStreamStart(warnings~ : Array[Warning])
  TranscriptionDelta(
    id~ : String?,
    delta~ : String,
    provider_metadata~ : Map[String, Json]
  )
  TranscriptionPartial(
    id~ : String?,
    text~ : String,
    start_second~ : Double?,
    duration_seconds~ : Double?,
    channel_index~ : Int?,
    provider_metadata~ : Map[String, Json]
  )
  TranscriptionFinal(
    id~ : String?,
    text~ : String,
    start_second~ : Double?,
    end_second~ : Double?,
    channel_index~ : Int?,
    provider_metadata~ : Map[String, Json]
  )
  TranscriptionResponseMetadata(ResponseMetadata)
  TranscriptionFinish(
    text~ : String,
    segments~ : Array[TranscriptionSegment],
    language~ : String?,
    duration_seconds~ : Double?,
    provider_metadata~ : Map[String, Json]
  )
  TranscriptionRaw(Json)
  TranscriptionStreamError(StreamErrorInfo)
} derive(Debug, Eq)

///|
/// Complete transcription returned by a provider.
pub(all) struct TranscriptionResponse {
  text : String
  segments : Array[TranscriptionSegment]
  language : String?
  duration_seconds : Double?
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct a transcription response without transport diagnostics.
pub fn TranscriptionResponse::new(
  text~ : String,
  segments? : Array[TranscriptionSegment] = [],
  language? : String,
  duration_seconds? : Double,
) -> TranscriptionResponse {
  {
    text,
    segments,
    language,
    duration_seconds,
    request: None,
    response: None,
    provider_metadata: Map([]),
    warnings: [],
  }
}

///|
/// Attach diagnostics to a transcription result.
pub fn TranscriptionResponse::with_diagnostics(
  self : TranscriptionResponse,
  request : RequestMetadata?,
  response : ResponseMetadata?,
  provider_metadata : Map[String, Json],
  warnings : Array[Warning],
) -> TranscriptionResponse {
  {
    text: self.text,
    segments: self.segments,
    language: self.language,
    duration_seconds: self.duration_seconds,
    request,
    response,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}

///|
/// Add HTTP metadata to a transcription result.
pub fn TranscriptionResponse::with_transport(
  self : TranscriptionResponse,
  request : RequestMetadata,
  response : ResponseMetadata,
) -> TranscriptionResponse {
  {
    text: self.text,
    segments: self.segments,
    language: self.language,
    duration_seconds: self.duration_seconds,
    request: Some(request),
    response: Some(merge_response_metadata(self.response, response)),
    provider_metadata: copy_provider_metadata(self.provider_metadata),
    warnings: copy_warnings(self.warnings),
  }
}
