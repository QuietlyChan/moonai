///|
/// Options for a V4 live speech translation call.
pub(all) struct SpeechTranslationModelV4StreamOptions {
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
/// Construct V4 speech translation options.
pub fn SpeechTranslationModelV4StreamOptions::new(
  audio~ : &AudioStream,
  input_audio_format~ : AudioFormat,
  target_language~ : String,
  source_language? : String,
  output_audio_format? : AudioFormat,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  include_raw_chunks? : Bool = false,
  cancellation_token? : CancellationToken,
) -> SpeechTranslationModelV4StreamOptions {
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
/// Lift legacy realtime translation options into the V4 contract.
pub fn SpeechTranslationModelV4StreamOptions::from_speech_translation_call_options(
  options : SpeechTranslationCallOptions,
) -> SpeechTranslationModelV4StreamOptions {
  SpeechTranslationModelV4StreamOptions::new(
    audio=options.audio,
    input_audio_format=options.input_audio_format,
    target_language=options.target_language,
    source_language?=options.source_language,
    output_audio_format?=options.output_audio_format,
    provider_options=options.provider_options,
    headers=options.headers,
    include_raw_chunks=options.include_raw_chunks,
    cancellation_token?=options.cancellation_token,
  )
}

///|
/// Convert V4 options at the explicit wire boundary.
pub fn SpeechTranslationModelV4StreamOptions::to_speech_translation_call_options(
  self : SpeechTranslationModelV4StreamOptions,
) -> SpeechTranslationCallOptions {
  SpeechTranslationCallOptions::new(
    audio=self.audio,
    input_audio_format=self.input_audio_format,
    target_language=self.target_language,
    source_language?=self.source_language,
    output_audio_format?=self.output_audio_format,
    provider_options=self.provider_options,
    headers=self.headers,
    include_raw_chunks=self.include_raw_chunks,
    cancellation_token?=self.cancellation_token,
  )
}

///|
/// Usage reported by a V4 speech translation model.
pub(all) struct SpeechTranslationModelV4Usage {
  input_audio_seconds : Double?
  input_audio_tokens : Int?
  output_audio_tokens : Int?
  input_text_tokens : Int?
  output_text_tokens : Int?
} derive(Debug, Eq)

///|
/// Construct V4 speech translation usage.
pub fn SpeechTranslationModelV4Usage::new(
  input_audio_seconds? : Double,
  input_audio_tokens? : Int,
  output_audio_tokens? : Int,
  input_text_tokens? : Int,
  output_text_tokens? : Int,
) -> SpeechTranslationModelV4Usage {
  {
    input_audio_seconds,
    input_audio_tokens,
    output_audio_tokens,
    input_text_tokens,
    output_text_tokens,
  }
}

///|
/// Normalized parts emitted by a V4 speech translation stream.
pub(all) enum SpeechTranslationModelV4StreamPart {
  SpeechTranslationV4StreamStart(warnings~ : Array[Warning])
  SpeechTranslationV4Audio(
    id~ : String?,
    audio~ : SpeechAudioData,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationV4OutputTextDelta(
    id~ : String?,
    delta~ : String,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationV4OutputTextFinal(
    id~ : String?,
    text~ : String,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationV4SourceTranscriptDelta(
    id~ : String?,
    delta~ : String,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationV4SourceTranscriptPartial(
    id~ : String?,
    text~ : String,
    start_second~ : Double?,
    end_second~ : Double?,
    channel_index~ : Int?,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationV4SourceTranscriptFinal(
    id~ : String?,
    text~ : String,
    start_second~ : Double?,
    end_second~ : Double?,
    channel_index~ : Int?,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationV4ResponseMetadata(ResponseMetadata)
  SpeechTranslationV4Finish(
    source_text~ : String,
    output_text~ : String,
    duration_in_seconds~ : Double?,
    usage~ : SpeechTranslationModelV4Usage?,
    provider_metadata~ : Map[String, Json]
  )
  SpeechTranslationV4Raw(Json)
  SpeechTranslationV4Error(String)
} derive(Debug, Eq)

///|
/// Convert an old wire event to the V4 vocabulary.
pub fn SpeechTranslationModelV4StreamPart::from_stream_event(
  event : SpeechTranslationStreamEvent,
) -> SpeechTranslationModelV4StreamPart {
  match event {
    SpeechTranslationStreamStart(warnings~) =>
      SpeechTranslationV4StreamStart(warnings~)
    SpeechTranslationAudio(id~, audio~, provider_metadata~) =>
      SpeechTranslationV4Audio(id~, audio~, provider_metadata~)
    SpeechTranslationOutputTextDelta(id~, delta~, provider_metadata~) =>
      SpeechTranslationV4OutputTextDelta(id~, delta~, provider_metadata~)
    SpeechTranslationOutputTextFinal(id~, text~, provider_metadata~) =>
      SpeechTranslationV4OutputTextFinal(id~, text~, provider_metadata~)
    SpeechTranslationSourceTranscriptDelta(id~, delta~, provider_metadata~) =>
      SpeechTranslationV4SourceTranscriptDelta(id~, delta~, provider_metadata~)
    SpeechTranslationSourceTranscriptPartial(
      id~,
      text~,
      start_second~,
      end_second~,
      channel_index~,
      provider_metadata~
    ) =>
      SpeechTranslationV4SourceTranscriptPartial(
        id~,
        text~,
        start_second~,
        end_second~,
        channel_index~,
        provider_metadata~,
      )
    SpeechTranslationSourceTranscriptFinal(
      id~,
      text~,
      start_second~,
      end_second~,
      channel_index~,
      provider_metadata~
    ) =>
      SpeechTranslationV4SourceTranscriptFinal(
        id~,
        text~,
        start_second~,
        end_second~,
        channel_index~,
        provider_metadata~,
      )
    SpeechTranslationResponseMetadata(value) =>
      SpeechTranslationV4ResponseMetadata(value)
    SpeechTranslationFinish(
      source_text~,
      output_text~,
      duration_seconds~,
      usage~,
      provider_metadata~
    ) =>
      SpeechTranslationV4Finish(
        source_text~,
        output_text~,
        duration_in_seconds=duration_seconds,
        usage=match usage {
          Some(value) =>
            Some(
              SpeechTranslationModelV4Usage::new(
                input_audio_seconds?=value.input_audio_seconds,
                input_audio_tokens?=value.input_audio_tokens,
                output_audio_tokens?=value.output_audio_tokens,
                input_text_tokens?=value.input_text_tokens,
                output_text_tokens?=value.output_text_tokens,
              ),
            )
          None => None
        },
        provider_metadata~,
      )
    SpeechTranslationRaw(value) => SpeechTranslationV4Raw(value)
    SpeechTranslationStreamError(message) => SpeechTranslationV4Error(message)
  }
}

///|
/// Convert a V4 stream part to the current wire event shape.
pub fn SpeechTranslationModelV4StreamPart::to_stream_event(
  self : SpeechTranslationModelV4StreamPart,
) -> SpeechTranslationStreamEvent {
  match self {
    SpeechTranslationV4StreamStart(warnings~) =>
      SpeechTranslationStreamStart(warnings~)
    SpeechTranslationV4Audio(id~, audio~, provider_metadata~) =>
      SpeechTranslationAudio(id~, audio~, provider_metadata~)
    SpeechTranslationV4OutputTextDelta(id~, delta~, provider_metadata~) =>
      SpeechTranslationOutputTextDelta(id~, delta~, provider_metadata~)
    SpeechTranslationV4OutputTextFinal(id~, text~, provider_metadata~) =>
      SpeechTranslationOutputTextFinal(id~, text~, provider_metadata~)
    SpeechTranslationV4SourceTranscriptDelta(id~, delta~, provider_metadata~) =>
      SpeechTranslationSourceTranscriptDelta(id~, delta~, provider_metadata~)
    SpeechTranslationV4SourceTranscriptPartial(
      id~,
      text~,
      start_second~,
      end_second~,
      channel_index~,
      provider_metadata~
    ) =>
      SpeechTranslationSourceTranscriptPartial(
        id~,
        text~,
        start_second~,
        end_second~,
        channel_index~,
        provider_metadata~,
      )
    SpeechTranslationV4SourceTranscriptFinal(
      id~,
      text~,
      start_second~,
      end_second~,
      channel_index~,
      provider_metadata~
    ) =>
      SpeechTranslationSourceTranscriptFinal(
        id~,
        text~,
        start_second~,
        end_second~,
        channel_index~,
        provider_metadata~,
      )
    SpeechTranslationV4ResponseMetadata(value) =>
      SpeechTranslationResponseMetadata(value)
    SpeechTranslationV4Finish(
      source_text~,
      output_text~,
      duration_in_seconds~,
      usage~,
      provider_metadata~
    ) =>
      SpeechTranslationFinish(
        source_text~,
        output_text~,
        duration_seconds=duration_in_seconds,
        usage=match usage {
          Some(value) =>
            Some(
              SpeechTranslationUsage::new(
                input_audio_seconds?=value.input_audio_seconds,
                input_audio_tokens?=value.input_audio_tokens,
                output_audio_tokens?=value.output_audio_tokens,
                input_text_tokens?=value.input_text_tokens,
                output_text_tokens?=value.output_text_tokens,
              ),
            )
          None => None
        },
        provider_metadata~,
      )
    SpeechTranslationV4Raw(value) => SpeechTranslationRaw(value)
    SpeechTranslationV4Error(message) => SpeechTranslationStreamError(message)
  }
}

///|
/// Metadata returned after a V4 speech translation call.
pub(all) struct SpeechTranslationModelV4StreamResult {
  request : RequestMetadata?
  response : ResponseMetadata?
} derive(Debug, Eq)

///|
/// Construct a V4 speech translation stream result.
pub fn SpeechTranslationModelV4StreamResult::new(
  request? : RequestMetadata,
  response? : ResponseMetadata,
) -> SpeechTranslationModelV4StreamResult {
  { request, response }
}

///|
/// Versioned streaming speech translation contract.
pub(open) trait SpeechTranslationModelV4 {
  fn specification_version(Self) -> String
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn do_stream(
    Self,
    SpeechTranslationModelV4StreamOptions,
    async (SpeechTranslationModelV4StreamPart) -> Unit,
  ) -> SpeechTranslationModelV4StreamResult
}
