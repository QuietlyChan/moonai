///|
/// Deterministic text-to-speech model for SDK consumer tests.
pub struct MockSpeechModel {
  priv provider_name : String
  priv model_id : String
  priv result : @provider.SpeechResponse
  priv mut captured_options : @provider.SpeechCallOptions?
}

///|
/// Construct a deterministic speech model.
pub fn MockSpeechModel::new(
  result : @provider.SpeechResponse,
  provider_name? : String = "mock",
  model_id? : String = "mock-speech-model",
) -> MockSpeechModel {
  { provider_name, model_id, result, captured_options: None }
}

///|
/// Return the latest normalized speech options.
pub fn MockSpeechModel::captured_options(
  self : MockSpeechModel,
) -> @provider.SpeechCallOptions? {
  self.captured_options
}

///|
pub impl @provider.SpeechWireModel for MockSpeechModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.SpeechWireModel for MockSpeechModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.SpeechWireModel for MockSpeechModel with fn generate(
  self,
  options,
) {
  self.captured_options = Some(options)
  self.result
}

///|
pub impl @provider.SpeechModelV4 for MockSpeechModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.SpeechModelV4 for MockSpeechModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.SpeechModelV4 for MockSpeechModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.SpeechModelV4 for MockSpeechModel with fn do_generate(
  self,
  options,
) {
  self.captured_options = Some(options.to_speech_call_options())
  @provider.SpeechModelV4Result::from_speech_response(self.result)
}

///|
/// Deterministic audio transcription model for SDK consumer tests.
pub struct MockTranscriptionModel {
  priv provider_name : String
  priv model_id : String
  priv result : @provider.TranscriptionResponse
  priv stream_events : Array[@provider.TranscriptionStreamEvent]
  priv stream_result : @provider.TranscriptionResponse
  priv mut captured_options : @provider.TranscriptionCallOptions?
  priv mut captured_stream_options : @provider.TranscriptionStreamOptions?
}

///|
/// Construct a deterministic transcription model.
pub fn MockTranscriptionModel::new(
  result : @provider.TranscriptionResponse,
  stream_events? : Array[@provider.TranscriptionStreamEvent] = [],
  stream_result? : @provider.TranscriptionResponse,
  provider_name? : String = "mock",
  model_id? : String = "mock-transcription-model",
) -> MockTranscriptionModel {
  {
    provider_name,
    model_id,
    result,
    stream_events: stream_events.copy(),
    stream_result: stream_result.unwrap_or(result),
    captured_options: None,
    captured_stream_options: None,
  }
}

///|
/// Return the latest normalized transcription options.
pub fn MockTranscriptionModel::captured_options(
  self : MockTranscriptionModel,
) -> @provider.TranscriptionCallOptions? {
  self.captured_options
}

///|
/// Return the latest normalized live transcription options.
pub fn MockTranscriptionModel::captured_stream_options(
  self : MockTranscriptionModel,
) -> @provider.TranscriptionStreamOptions? {
  self.captured_stream_options
}

///|
pub impl @provider.TranscriptionWireModel for MockTranscriptionModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.TranscriptionWireModel for MockTranscriptionModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.TranscriptionWireModel for MockTranscriptionModel with fn generate(
  self,
  options,
) {
  self.captured_options = Some(options)
  self.result
}

///|
pub impl @provider.TranscriptionWireModel for MockTranscriptionModel with fn stream(
  self,
  options,
  on_event,
) {
  self.captured_stream_options = Some(options)
  for event in self.stream_events {
    on_event(event)
  }
  self.stream_result
}

///|
pub impl @provider.TranscriptionModelV4 for MockTranscriptionModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.TranscriptionModelV4 for MockTranscriptionModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.TranscriptionModelV4 for MockTranscriptionModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.TranscriptionModelV4 for MockTranscriptionModel with fn do_generate(
  self,
  options,
) {
  self.captured_options = Some(options.to_transcription_call_options())
  @provider.TranscriptionModelV4Result::from_transcription_response(self.result)
}

///|
pub impl @provider.TranscriptionModelV4 for MockTranscriptionModel with fn do_stream(
  self,
  options,
  on_part,
) {
  self.captured_stream_options = Some(options.to_transcription_stream_options())
  for event in self.stream_events {
    on_part(@provider.TranscriptionModelV4StreamPart::from_stream_event(event))
  }
  @provider.TranscriptionModelV4StreamResult::new(
    request?=self.stream_result.request,
    response?=self.stream_result.response,
  )
}

///|
/// Deterministic streaming speech translation model for SDK consumer tests.
pub struct MockSpeechTranslationModel {
  priv provider_name : String
  priv model_id : String
  priv events : Array[@provider.SpeechTranslationStreamEvent]
  priv result : @provider.SpeechTranslationResponse
  priv mut captured_target_language : String?
}

///|
/// Construct a deterministic speech translation model.
pub fn MockSpeechTranslationModel::new(
  events : Array[@provider.SpeechTranslationStreamEvent],
  result : @provider.SpeechTranslationResponse,
  provider_name? : String = "mock",
  model_id? : String = "mock-translation-model",
) -> MockSpeechTranslationModel {
  { provider_name, model_id, events, result, captured_target_language: None }
}

///|
/// Return the target language from the latest stream call.
pub fn MockSpeechTranslationModel::captured_target_language(
  self : MockSpeechTranslationModel,
) -> String? {
  self.captured_target_language
}

///|
pub impl @provider.SpeechTranslationWireModel for MockSpeechTranslationModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.SpeechTranslationWireModel for MockSpeechTranslationModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.SpeechTranslationWireModel for MockSpeechTranslationModel with fn stream(
  self,
  options,
  on_event,
) {
  self.captured_target_language = Some(options.target_language)
  for event in self.events {
    on_event(event)
  }
  self.result
}

///|
pub impl @provider.SpeechTranslationModelV4 for MockSpeechTranslationModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.SpeechTranslationModelV4 for MockSpeechTranslationModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.SpeechTranslationModelV4 for MockSpeechTranslationModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.SpeechTranslationModelV4 for MockSpeechTranslationModel with fn do_stream(
  self,
  options,
  on_part,
) {
  self.captured_target_language = Some(options.target_language)
  for event in self.events {
    on_part(
      @provider.SpeechTranslationModelV4StreamPart::from_stream_event(event),
    )
  }
  @provider.SpeechTranslationModelV4StreamResult::new(
    request?=self.result.request,
    response?=self.result.response,
  )
}
