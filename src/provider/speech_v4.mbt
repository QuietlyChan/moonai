///|
/// Versioned call options for an AI SDK V4 speech model.
///
/// Provider options remain keyed by provider name, while retry and
/// cancellation settings are MoonBit runtime extensions used by transports.
pub(all) struct SpeechModelV4CallOptions {
  text : String
  voice : String?
  output_format : String?
  instructions : String?
  speed : Double?
  language : String?
  provider_options : Map[String, Json]
  headers : Map[String, String]
  retry_policy : RetryPolicy
  cancellation_token : CancellationToken?
} derive(Debug)

///|
/// Construct V4 speech call options.
pub fn SpeechModelV4CallOptions::new(
  text~ : String,
  voice? : String,
  output_format? : String,
  instructions? : String,
  speed? : Double,
  language? : String,
  provider_options? : Map[String, Json] = Map([]),
  headers? : Map[String, String] = Map([]),
  retry_policy? : RetryPolicy = RetryPolicy::standard(),
  cancellation_token? : CancellationToken,
) -> SpeechModelV4CallOptions {
  {
    text,
    voice,
    output_format,
    instructions,
    speed,
    language,
    provider_options,
    headers,
    retry_policy,
    cancellation_token,
  }
}

///|
/// Convert V4 options at the explicit wire-adapter boundary.
pub fn SpeechModelV4CallOptions::to_speech_call_options(
  self : SpeechModelV4CallOptions,
) -> SpeechCallOptions {
  SpeechCallOptions::new(
    text=self.text,
    voice?=self.voice,
    output_format?=self.output_format,
    instructions?=self.instructions,
    speed?=self.speed,
    language?=self.language,
    headers=self.headers,
    provider_options=self.provider_options,
    retry_policy=self.retry_policy,
    cancellation_token?=self.cancellation_token,
  )
}

///|
/// Result returned by a V4 speech model.
pub(all) struct SpeechModelV4Result {
  audio : SpeechAudioData
  warnings : Array[Warning]
  request : RequestMetadata?
  response : ResponseMetadata?
  provider_metadata : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct a V4 speech result.
pub fn SpeechModelV4Result::new(
  audio~ : SpeechAudioData,
  warnings? : Array[Warning] = [],
  request? : RequestMetadata,
  response? : ResponseMetadata,
  provider_metadata? : Map[String, Json] = Map([]),
) -> SpeechModelV4Result {
  {
    audio,
    warnings: copy_warnings(warnings),
    request,
    response,
    provider_metadata: copy_provider_metadata(provider_metadata),
  }
}

///|
/// Convert an existing wire response at an explicit adapter boundary.
pub fn SpeechModelV4Result::from_speech_response(
  response : SpeechResponse,
) -> SpeechModelV4Result {
  SpeechModelV4Result::new(
    audio=response.audio,
    warnings=response.warnings,
    request?=response.request,
    response?=response.response,
    provider_metadata=response.provider_metadata,
  )
}

///|
/// Convert a V4 result to the legacy wire response shape.
pub fn SpeechModelV4Result::to_speech_response(
  self : SpeechModelV4Result,
) -> SpeechResponse {
  SpeechResponse::new(audio=self.audio, media_type="application/octet-stream").with_diagnostics(
    self.request,
    self.response,
    self.provider_metadata,
    self.warnings,
  )
}

///|
/// Versioned provider contract for text-to-speech generation.
pub(open) trait SpeechModelV4 {
  fn specification_version(Self) -> String
  fn provider(Self) -> String
  fn model_id(Self) -> String
  async fn do_generate(Self, SpeechModelV4CallOptions) -> SpeechModelV4Result
}
