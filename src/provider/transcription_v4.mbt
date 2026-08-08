///|
/// Versioned options for one buffered transcription call.
pub(all) struct TranscriptionModelV4CallOptions {
  audio : TranscriptionAudio
  media_type : String
  provider_options : Map[String, Json]
  headers : Map[String, String]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct V4 buffered transcription options.
pub fn TranscriptionModelV4CallOptions::new(
  audio~ : TranscriptionAudio,
  media_type~ : String,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> TranscriptionModelV4CallOptions {
  {
    audio,
    media_type,
    provider_options,
    headers,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Lift buffered legacy transcription options into the V4 contract.
pub fn TranscriptionModelV4CallOptions::from_transcription_call_options(
  options : TranscriptionCallOptions,
) -> TranscriptionModelV4CallOptions {
  TranscriptionModelV4CallOptions::new(
    audio=options.audio,
    media_type=options.media_type,
    provider_options=options.provider_options,
    headers=options.headers,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}

///|
/// Convert V4 buffered options at the wire boundary.
pub fn TranscriptionModelV4CallOptions::to_transcription_call_options(
  self : TranscriptionModelV4CallOptions,
) -> TranscriptionCallOptions {
  TranscriptionCallOptions::new(
    audio=self.audio,
    media_type=self.media_type,
    headers=self.headers,
    provider_options=self.provider_options,
    retry_policy=self.retry_policy,
    cancellation_token?=self.cancellation_token,
  )
}

///|
/// Lossless V4 transcription result.
pub(all) struct TranscriptionModelV4Result {
  text : String
  segments : Array[TranscriptionSegment]
  language : String?
  duration_in_seconds : Double?
  warnings : Array[Warning]
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a V4 transcription result.
pub fn TranscriptionModelV4Result::new(
  text~ : String,
  segments? : Array[TranscriptionSegment] = [],
  language? : String,
  duration_in_seconds? : Double,
  warnings? : Array[Warning] = [],
  request? : RequestMetadata,
  response? : ResponseMetadata,
  provider_metadata? : Map[String, Json] = Map([]),
) -> TranscriptionModelV4Result {
  {
    text,
    segments,
    language,
    duration_in_seconds,
    warnings: copy_warnings(warnings),
    request,
    response,
    provider_metadata: copy_provider_metadata(provider_metadata),
  }
}

///|
/// Convert an existing wire result at the explicit adapter boundary.
pub fn TranscriptionModelV4Result::from_transcription_response(
  response : TranscriptionResponse,
) -> TranscriptionModelV4Result {
  TranscriptionModelV4Result::new(
    text=response.text,
    segments=response.segments,
    language?=response.language,
    duration_in_seconds?=response.duration_seconds,
    warnings=response.warnings,
    request?=response.request,
    response?=response.response,
    provider_metadata=response.provider_metadata,
  )
}

///|
/// Convert a V4 result to the current wire response shape.
pub fn TranscriptionModelV4Result::to_transcription_response(
  self : TranscriptionModelV4Result,
) -> TranscriptionResponse {
  TranscriptionResponse::new(
    text=self.text,
    segments=self.segments,
    language?=self.language,
    duration_seconds?=self.duration_in_seconds,
  ).with_diagnostics(
    self.request,
    self.response,
    self.provider_metadata,
    self.warnings,
  )
}

///|
/// Options for a live V4 transcription stream.
pub(all) struct TranscriptionModelV4StreamOptions {
  audio : &AudioStream
  input_audio_format : AudioFormat
  provider_options : Map[String, Json]
  headers : Map[String, String]
  include_raw_chunks : Bool
  cancellation_token : CancellationToken?
}

///|
/// Construct live V4 transcription options.
pub fn TranscriptionModelV4StreamOptions::new(
  audio~ : &AudioStream,
  input_audio_format~ : AudioFormat,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  include_raw_chunks? : Bool = false,
  cancellation_token? : CancellationToken,
) -> TranscriptionModelV4StreamOptions {
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
/// Lift realtime legacy transcription options into the V4 contract.
pub fn TranscriptionModelV4StreamOptions::from_transcription_stream_options(
  options : TranscriptionStreamOptions,
) -> TranscriptionModelV4StreamOptions {
  TranscriptionModelV4StreamOptions::new(
    audio=options.audio,
    input_audio_format=options.input_audio_format,
    provider_options=options.provider_options,
    headers=options.headers,
    include_raw_chunks=options.include_raw_chunks,
    cancellation_token?=options.cancellation_token,
  )
}

///|
/// Convert live V4 options at the wire boundary.
pub fn TranscriptionModelV4StreamOptions::to_transcription_stream_options(
  self : TranscriptionModelV4StreamOptions,
) -> TranscriptionStreamOptions {
  TranscriptionStreamOptions::new(
    audio=self.audio,
    input_audio_format=self.input_audio_format,
    provider_options=self.provider_options,
    headers=self.headers,
    include_raw_chunks=self.include_raw_chunks,
    cancellation_token?=self.cancellation_token,
  )
}

///|
/// Normalized parts emitted by a V4 transcription stream.
pub(all) enum TranscriptionModelV4StreamPart {
  TranscriptionV4StreamStart(warnings~ : Array[Warning])
  TranscriptionV4TranscriptDelta(
    id~ : String?,
    delta~ : String,
    provider_metadata~ : Map[String, Json]
  )
  TranscriptionV4TranscriptPartial(
    id~ : String?,
    text~ : String,
    start_second~ : Double?,
    duration_in_seconds~ : Double?,
    channel_index~ : Int?,
    provider_metadata~ : Map[String, Json]
  )
  TranscriptionV4TranscriptFinal(
    id~ : String?,
    text~ : String,
    start_second~ : Double?,
    end_second~ : Double?,
    channel_index~ : Int?,
    provider_metadata~ : Map[String, Json]
  )
  TranscriptionV4ResponseMetadata(ResponseMetadata)
  TranscriptionV4Finish(
    text~ : String,
    segments~ : Array[TranscriptionSegment],
    language~ : String?,
    duration_in_seconds~ : Double?,
    provider_metadata~ : Map[String, Json]
  )
  TranscriptionV4Raw(Json)
  TranscriptionV4Error(StreamErrorInfo)
} derive(Debug, Eq)

///|
/// Convert an old wire stream event to the V4 stream vocabulary.
pub fn TranscriptionModelV4StreamPart::from_stream_event(
  event : TranscriptionStreamEvent,
) -> TranscriptionModelV4StreamPart {
  match event {
    TranscriptionStreamStart(warnings~) => TranscriptionV4StreamStart(warnings~)
    TranscriptionDelta(id~, delta~, provider_metadata~) =>
      TranscriptionV4TranscriptDelta(id~, delta~, provider_metadata~)
    TranscriptionPartial(
      id~,
      text~,
      start_second~,
      duration_seconds~,
      channel_index~,
      provider_metadata~
    ) =>
      TranscriptionV4TranscriptPartial(
        id~,
        text~,
        start_second~,
        duration_in_seconds=duration_seconds,
        channel_index~,
        provider_metadata~,
      )
    TranscriptionFinal(
      id~,
      text~,
      start_second~,
      end_second~,
      channel_index~,
      provider_metadata~
    ) =>
      TranscriptionV4TranscriptFinal(
        id~,
        text~,
        start_second~,
        end_second~,
        channel_index~,
        provider_metadata~,
      )
    TranscriptionResponseMetadata(value) =>
      TranscriptionV4ResponseMetadata(value)
    TranscriptionFinish(
      text~,
      segments~,
      language~,
      duration_seconds~,
      provider_metadata~
    ) =>
      TranscriptionV4Finish(
        text~,
        segments~,
        language~,
        duration_in_seconds=duration_seconds,
        provider_metadata~,
      )
    TranscriptionRaw(value) => TranscriptionV4Raw(value)
    TranscriptionStreamError(error) => TranscriptionV4Error(error)
  }
}

///|
/// Convert a V4 stream part to the current wire event shape.
pub fn TranscriptionModelV4StreamPart::to_stream_event(
  self : TranscriptionModelV4StreamPart,
) -> TranscriptionStreamEvent {
  match self {
    TranscriptionV4StreamStart(warnings~) => TranscriptionStreamStart(warnings~)
    TranscriptionV4TranscriptDelta(id~, delta~, provider_metadata~) =>
      TranscriptionDelta(id~, delta~, provider_metadata~)
    TranscriptionV4TranscriptPartial(
      id~,
      text~,
      start_second~,
      duration_in_seconds~,
      channel_index~,
      provider_metadata~
    ) =>
      TranscriptionPartial(
        id~,
        text~,
        start_second~,
        duration_seconds=duration_in_seconds,
        channel_index~,
        provider_metadata~,
      )
    TranscriptionV4TranscriptFinal(
      id~,
      text~,
      start_second~,
      end_second~,
      channel_index~,
      provider_metadata~
    ) =>
      TranscriptionFinal(
        id~,
        text~,
        start_second~,
        end_second~,
        channel_index~,
        provider_metadata~,
      )
    TranscriptionV4ResponseMetadata(value) =>
      TranscriptionResponseMetadata(value)
    TranscriptionV4Finish(
      text~,
      segments~,
      language~,
      duration_in_seconds~,
      provider_metadata~
    ) =>
      TranscriptionFinish(
        text~,
        segments~,
        language~,
        duration_seconds=duration_in_seconds,
        provider_metadata~,
      )
    TranscriptionV4Raw(value) => TranscriptionRaw(value)
    TranscriptionV4Error(error) => TranscriptionStreamError(error)
  }
}

///|
/// Metadata returned after a V4 live transcription call.
pub(all) struct TranscriptionModelV4StreamResult {
  request : RequestMetadata?
  response : ResponseMetadata?
} derive(Debug, Eq)

///|
/// Construct a V4 transcription stream result.
pub fn TranscriptionModelV4StreamResult::new(
  request? : RequestMetadata,
  response? : ResponseMetadata,
) -> TranscriptionModelV4StreamResult {
  { request, response }
}

///|
/// Versioned provider contract for buffered and live transcription.
pub(open) trait TranscriptionModelV4 {
  fn specification_version(Self) -> String
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn do_generate(Self, TranscriptionModelV4CallOptions) -> TranscriptionModelV4Result
  async fn do_stream(
    Self,
    TranscriptionModelV4StreamOptions,
    async (TranscriptionModelV4StreamPart) -> Unit,
  ) -> TranscriptionModelV4StreamResult
}
