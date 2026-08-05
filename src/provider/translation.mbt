///|
/// Provider-neutral options for one live speech translation session.
pub struct SpeechTranslationCallOptions {
  audio : &AudioStream
  input_audio_format : AudioFormat
  target_language : String
  source_language : String?
  output_audio_format : AudioFormat?
  provider_options : Map[String, Json]
  headers : Map[String, String]
  include_raw_chunks : Bool
  cancellation_token : CancellationToken?
}

///|
/// Construct normalized streaming speech translation options.
pub fn SpeechTranslationCallOptions::new(
  audio~ : &AudioStream,
  input_audio_format~ : AudioFormat,
  target_language~ : String,
  source_language? : String,
  output_audio_format? : AudioFormat,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  include_raw_chunks? : Bool = false,
  cancellation_token? : CancellationToken,
) -> SpeechTranslationCallOptions {
  {
    audio,
    input_audio_format,
    target_language,
    source_language,
    output_audio_format,
    provider_options,
    headers,
    include_raw_chunks,
    cancellation_token,
  }
}

///|
/// Usage values reported by a speech translation provider. Every field is
/// optional because providers expose different audio and text accounting.
pub(all) struct SpeechTranslationUsage {
  input_audio_seconds : Double?
  input_audio_tokens : Int?
  output_audio_tokens : Int?
  input_text_tokens : Int?
  output_text_tokens : Int?
} derive(Debug, Eq)

///|
/// Construct an empty usage record that can be selectively populated.
pub fn SpeechTranslationUsage::new(
  input_audio_seconds? : Double,
  input_audio_tokens? : Int,
  output_audio_tokens? : Int,
  input_text_tokens? : Int,
  output_text_tokens? : Int,
) -> SpeechTranslationUsage {
  {
    input_audio_seconds,
    input_audio_tokens,
    output_audio_tokens,
    input_text_tokens,
    output_text_tokens,
  }
}

///|
/// Event protocol for streaming source transcripts, translated text, and
/// translated audio.
pub(all) enum SpeechTranslationStreamEvent {
  SpeechTranslationStreamStart(warnings~ : Array[Warning])
  SpeechTranslationAudio(
    id~ : String?,
    audio~ : SpeechAudioData,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationOutputTextDelta(
    id~ : String?,
    delta~ : String,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationOutputTextFinal(
    id~ : String?,
    text~ : String,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationSourceTranscriptDelta(
    id~ : String?,
    delta~ : String,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationSourceTranscriptPartial(
    id~ : String?,
    text~ : String,
    start_second~ : Double?,
    end_second~ : Double?,
    channel_index~ : Int?,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationSourceTranscriptFinal(
    id~ : String?,
    text~ : String,
    start_second~ : Double?,
    end_second~ : Double?,
    channel_index~ : Int?,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationResponseMetadata(ResponseMetadata)
  SpeechTranslationFinish(
    source_text~ : String,
    output_text~ : String,
    duration_seconds~ : Double?,
    usage~ : SpeechTranslationUsage?,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationRaw(Json)
  SpeechTranslationStreamError(String)
} derive(Debug, Eq)

///|
/// Fully accumulated result of a speech translation stream.
pub(all) struct SpeechTranslationResponse {
  source_text : String
  output_text : String
  duration_seconds : Double?
  usage : SpeechTranslationUsage?
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct a speech translation result without diagnostics.
pub fn SpeechTranslationResponse::new(
  source_text~ : String,
  output_text~ : String,
  duration_seconds? : Double,
  usage? : SpeechTranslationUsage,
) -> SpeechTranslationResponse {
  {
    source_text,
    output_text,
    duration_seconds,
    usage,
    request: None,
    response: None,
    provider_metadata: Map([]),
    warnings: [],
  }
}

///|
/// Attach request, response, provider metadata, and warnings.
pub fn SpeechTranslationResponse::with_diagnostics(
  self : SpeechTranslationResponse,
  request : RequestMetadata?,
  response : ResponseMetadata?,
  provider_metadata : Map[String, Json],
  warnings : Array[Warning],
) -> SpeechTranslationResponse {
  {
    source_text: self.source_text,
    output_text: self.output_text,
    duration_seconds: self.duration_seconds,
    usage: self.usage,
    request,
    response,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}
