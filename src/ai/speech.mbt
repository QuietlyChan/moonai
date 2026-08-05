///|
/// Generate speech audio from text.
pub async fn generate_speech(
  model : &SpeechModelV4,
  text : String,
  voice? : String,
  output_format? : String,
  instructions? : String,
  speed? : Double,
  language? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> SpeechResponse {
  check_cancellation(cancellation_token)
  guard text != "" else { fail("generate_speech requires non-empty text") }
  let result = model.do_generate(
    @provider.SpeechModelV4CallOptions::new(
      text~,
      voice?,
      output_format?,
      instructions?,
      speed?,
      language?,
      headers~,
      provider_options~,
      retry_policy~,
      cancellation_token?,
    ),
  )
  guard !result.audio.is_empty() else {
    fail("speech provider returned an empty audio payload")
  }
  SpeechResponse::new(
    audio=result.audio,
    media_type=speech_output_media_type(output_format.unwrap_or("mp3")),
  ).with_diagnostics(
    result.request,
    result.response,
    result.provider_metadata,
    result.warnings,
  )
}

///|
fn speech_output_media_type(format : String) -> String {
  match format {
    "mp3" => "audio/mpeg"
    "opus" => "audio/opus"
    "aac" => "audio/aac"
    "flac" => "audio/flac"
    "wav" => "audio/wav"
    "pcm" => "audio/pcm"
    _ => "audio/mpeg"
  }
}

///|
/// AI SDK-style camel-case spelling for `generate_speech`.
pub async fn generateSpeech(
  model : &SpeechModelV4,
  text : String,
  voice? : String,
  output_format? : String,
  instructions? : String,
  speed? : Double,
  language? : String,
  headers? : Map[String, String] = Map([]),
  provider_options? : Map[String, Json] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> SpeechResponse {
  generate_speech(
    model,
    text,
    voice?,
    output_format?,
    instructions?,
    speed?,
    language?,
    headers~,
    provider_options~,
    retry_policy~,
    cancellation_token?,
  )
}
