///|
/// Transcribe one inline audio payload.
pub async fn transcribe(
  model : &TranscriptionModelV4,
  audio~ : TranscriptionAudio,
  media_type~ : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> TranscriptionResponse {
  check_cancellation(cancellation_token)
  guard media_type.trim() != "" else {
    fail("transcribe requires a non-empty media_type")
  }
  let result = model.do_generate(
    @provider.TranscriptionModelV4CallOptions::new(
      audio~,
      media_type~,
      headers~,
      provider_options~,
      retry_policy~,
      cancellation_token?,
    ),
  )
  guard result.text != "" else {
    fail("transcription provider returned an empty transcript")
  }
  result.to_transcription_response()
}

///|
/// Stream live audio transcription through a provider-neutral model.
pub async fn stream_transcribe(
  model : &TranscriptionModelV4,
  audio~ : &AudioStream,
  input_audio_format~ : AudioFormat,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  include_raw_chunks? : Bool = false,
  on_event? : async (TranscriptionStreamEvent) -> Unit = _ => (),
  cancellation_token? : CancellationToken,
) -> TranscriptionResponse {
  check_cancellation(cancellation_token)
  guard input_audio_format.media_type.trim() != "" else {
    fail("stream_transcribe requires a non-empty audio format")
  }
  let warnings : Array[Warning] = []
  let provider_metadata : Map[String, Json] = Map([])
  let final_text : Ref[String?] = Ref(None)
  let final_segments : Ref[Array[@provider.TranscriptionSegment]] = Ref([])
  let final_language : Ref[String?] = Ref(None)
  let final_duration : Ref[Double?] = Ref(None)
  let response_metadata : Ref[ResponseMetadata?] = Ref(None)
  let transcript = StringBuilder::new()
  let stream_result = model.do_stream(
    @provider.TranscriptionModelV4StreamOptions::new(
      audio~,
      input_audio_format~,
      provider_options~,
      headers~,
      include_raw_chunks~,
      cancellation_token?,
    ),
    part => {
      match part {
        @provider.TranscriptionV4StreamStart(warnings=values) =>
          for warning in values {
            warnings.push(warning)
          }
        @provider.TranscriptionV4TranscriptDelta(delta~, ..) =>
          transcript.write_string(delta)
        @provider.TranscriptionV4ResponseMetadata(metadata) =>
          response_metadata.val = merge_optional_response_metadata(
            response_metadata.val,
            Some(metadata),
          )
        @provider.TranscriptionV4Finish(
          text~,
          segments~,
          language~,
          duration_in_seconds~,
          provider_metadata=metadata
        ) => {
          final_text.val = Some(text)
          final_segments.val = segments
          final_language.val = language
          final_duration.val = duration_in_seconds
          for entry in metadata.iter2() {
            provider_metadata[entry.0] = entry.1
          }
        }
        _ => ()
      }
      on_event(part.to_stream_event())
    },
  )
  let text = final_text.val.unwrap_or(transcript.to_string())
  TranscriptionResponse::new(
    text~,
    segments=final_segments.val,
    language?=final_language.val,
    duration_seconds?=final_duration.val,
  ).with_diagnostics(
    stream_result.request,
    merge_optional_response_metadata(
      stream_result.response,
      response_metadata.val,
    ),
    provider_metadata,
    warnings,
  )
}

///|
/// AI SDK experimental spelling for streaming transcription.
pub async fn experimental_streamTranscribe(
  model : &TranscriptionModelV4,
  audio~ : &AudioStream,
  input_audio_format~ : AudioFormat,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  include_raw_chunks? : Bool = false,
  on_event? : async (TranscriptionStreamEvent) -> Unit = _ => (),
  cancellation_token? : CancellationToken,
) -> TranscriptionResponse {
  stream_transcribe(
    model,
    audio~,
    input_audio_format~,
    provider_options~,
    headers~,
    include_raw_chunks~,
    on_event~,
    cancellation_token?,
  )
}

///|
/// Camel-case alias for AI SDK-style consumers.
pub async fn streamTranscribe(
  model : &TranscriptionModelV4,
  audio~ : &AudioStream,
  input_audio_format~ : AudioFormat,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  include_raw_chunks? : Bool = false,
  on_event? : async (TranscriptionStreamEvent) -> Unit = _ => (),
  cancellation_token? : CancellationToken,
) -> TranscriptionResponse {
  stream_transcribe(
    model,
    audio~,
    input_audio_format~,
    provider_options~,
    headers~,
    include_raw_chunks~,
    on_event~,
    cancellation_token?,
  )
}
