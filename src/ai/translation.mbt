///|
/// Stream live speech translation through a provider-neutral model.
pub async fn stream_speech_translation(
  model : &SpeechTranslationModelV4,
  audio~ : &AudioStream,
  input_audio_format~ : AudioFormat,
  target_language~ : String,
  source_language? : String,
  output_audio_format? : AudioFormat,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  include_raw_chunks? : Bool = false,
  on_event? : async (SpeechTranslationStreamEvent) -> Unit = _ => (),
  cancellation_token? : CancellationToken,
) -> SpeechTranslationResponse {
  check_cancellation(cancellation_token)
  guard target_language.trim() != "" else {
    fail("target_language is required for speech translation")
  }
  let warnings : Array[Warning] = []
  let provider_metadata : Map[String, Json] = Map([])
  let final_source_text : Ref[String?] = Ref(None)
  let final_output_text : Ref[String?] = Ref(None)
  let final_duration : Ref[Double?] = Ref(None)
  let final_usage : Ref[@provider.SpeechTranslationModelV4Usage?] = Ref(None)
  let response_metadata : Ref[ResponseMetadata?] = Ref(None)
  let source_text = StringBuilder::new()
  let output_text = StringBuilder::new()
  let stream_result = model.do_stream(
    @provider.SpeechTranslationModelV4StreamOptions::new(
      audio~,
      input_audio_format~,
      target_language~,
      source_language?,
      output_audio_format?,
      provider_options~,
      headers~,
      include_raw_chunks~,
      cancellation_token?,
    ),
    part => {
      match part {
        @provider.SpeechTranslationV4StreamStart(warnings=values) =>
          for warning in values {
            warnings.push(warning)
          }
        @provider.SpeechTranslationV4SourceTranscriptDelta(delta~, ..) =>
          source_text.write_string(delta)
        @provider.SpeechTranslationV4OutputTextDelta(delta~, ..) =>
          output_text.write_string(delta)
        @provider.SpeechTranslationV4ResponseMetadata(metadata) =>
          response_metadata.val = merge_optional_response_metadata(
            response_metadata.val,
            Some(metadata),
          )
        @provider.SpeechTranslationV4Finish(
          source_text=source,
          output_text=output,
          duration_in_seconds~,
          usage~,
          provider_metadata=metadata
        ) => {
          final_source_text.val = Some(source)
          final_output_text.val = Some(output)
          final_duration.val = duration_in_seconds
          final_usage.val = usage
          for entry in metadata.iter2() {
            provider_metadata[entry.0] = entry.1
          }
        }
        _ => ()
      }
      on_event(part.to_stream_event())
    },
  )
  let usage = match final_usage.val {
    Some(value) =>
      Some(
        @provider.SpeechTranslationUsage::new(
          input_audio_seconds?=value.input_audio_seconds,
          input_audio_tokens?=value.input_audio_tokens,
          output_audio_tokens?=value.output_audio_tokens,
          input_text_tokens?=value.input_text_tokens,
          output_text_tokens?=value.output_text_tokens,
        ),
      )
    None => None
  }
  SpeechTranslationResponse::new(
    source_text=final_source_text.val.unwrap_or(source_text.to_string()),
    output_text=final_output_text.val.unwrap_or(output_text.to_string()),
    duration_seconds?=final_duration.val,
    usage?,
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
/// Camel-case alias for AI SDK-style consumers.
pub async fn streamSpeechTranslation(
  model : &SpeechTranslationModelV4,
  audio~ : &AudioStream,
  input_audio_format~ : AudioFormat,
  target_language~ : String,
  source_language? : String,
  output_audio_format? : AudioFormat,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  include_raw_chunks? : Bool = false,
  on_event? : async (SpeechTranslationStreamEvent) -> Unit = _ => (),
  cancellation_token? : CancellationToken,
) -> SpeechTranslationResponse {
  stream_speech_translation(
    model,
    audio~,
    input_audio_format~,
    target_language~,
    source_language?,
    output_audio_format?,
    provider_options~,
    headers~,
    include_raw_chunks~,
    on_event~,
    cancellation_token?,
  )
}
