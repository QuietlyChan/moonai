///|
/// Output modality requested from a realtime model.
#derive(Debug, Eq)
pub(all) enum RealtimeOutputModality {
  RealtimeText
  RealtimeAudio
}

///|
/// Input or output transcription settings for a realtime session.
#derive(Debug, Eq)
pub(all) struct RealtimeAudioTranscriptionConfig {
  model : String?
  language : String?
  prompt : String?
}

///|
/// Construct realtime audio transcription settings.
pub fn RealtimeAudioTranscriptionConfig::new(
  model? : String,
  language? : String,
  prompt? : String,
) -> RealtimeAudioTranscriptionConfig {
  { model, language, prompt, }
}

///|
/// Voice activity detection settings. `Disabled` represents push-to-talk.
#derive(Debug, Eq)
pub(all) enum RealtimeTurnDetection {
  RealtimeTurnDetectionDisabled
  RealtimeServerVad(
    threshold~ : Double?,
    silence_duration_ms~ : Int32?,
    prefix_padding_ms~ : Int32?
  )
  RealtimeSemanticVad(
    threshold~ : Double?,
    silence_duration_ms~ : Int32?,
    prefix_padding_ms~ : Int32?
  )
}

///|
/// Construct server-side voice activity detection settings.
pub fn RealtimeTurnDetection::server_vad(
  threshold? : Double,
  silence_duration_ms? : Int32,
  prefix_padding_ms? : Int32,
) -> RealtimeTurnDetection {
  RealtimeServerVad(threshold~, silence_duration_ms~, prefix_padding_ms~)
}

///|
/// Construct semantic voice activity detection settings.
pub fn RealtimeTurnDetection::semantic_vad(
  threshold? : Double,
  silence_duration_ms? : Int32,
  prefix_padding_ms? : Int32,
) -> RealtimeTurnDetection {
  RealtimeSemanticVad(threshold~, silence_duration_ms~, prefix_padding_ms~)
}

///|
/// Disable server voice activity detection.
pub fn RealtimeTurnDetection::disabled() -> RealtimeTurnDetection {
  RealtimeTurnDetectionDisabled
}

///|
/// Function tool exposed to a realtime model.
#derive(Debug, Eq)
pub(all) struct RealtimeToolDefinition {
  name : String
  description : String?
  parameters : Json
}

///|
/// Construct a realtime function tool definition.
pub fn RealtimeToolDefinition::new(
  name~ : String,
  parameters~ : Json,
  description? : String,
) -> RealtimeToolDefinition {
  { name, description, parameters, }
}

///|
/// Provider-neutral realtime session configuration.
#derive(Debug, Eq)
pub(all) struct RealtimeSessionConfig {
  instructions : String?
  voice : String?
  output_modalities : Array[RealtimeOutputModality]?
  input_audio_format : AudioFormat?
  input_audio_transcription : RealtimeAudioTranscriptionConfig?
  output_audio_transcription : RealtimeAudioTranscriptionConfig?
  output_audio_format : AudioFormat?
  turn_detection : RealtimeTurnDetection?
  tools : Array[RealtimeToolDefinition]
  provider_options : Map[String, Json]
}

///|
/// Construct a realtime session configuration.
pub fn RealtimeSessionConfig::new(
  instructions? : String,
  voice? : String,
  output_modalities? : Array[RealtimeOutputModality],
  input_audio_format? : AudioFormat,
  input_audio_transcription? : RealtimeAudioTranscriptionConfig,
  output_audio_transcription? : RealtimeAudioTranscriptionConfig,
  output_audio_format? : AudioFormat,
  turn_detection? : RealtimeTurnDetection,
  tools? : Array[RealtimeToolDefinition] = [],
  provider_options? : Map[String, Json] = Map([]),
) -> RealtimeSessionConfig {
  {
    instructions,
    voice,
    output_modalities,
    input_audio_format,
    input_audio_transcription,
    output_audio_transcription,
    output_audio_format,
    turn_detection,
    tools,
    provider_options,
  }
}

///|
/// Conversation item sent from a realtime client.
#derive(Debug, Eq)
pub(all) enum RealtimeConversationItem {
  RealtimeTextMessage(text~ : String)
  RealtimeAudioMessage(audio~ : String)
  RealtimeFunctionCallOutput(
    call_id~ : String,
    name~ : String?,
    output~ : String
  )
}

///|
/// Optional overrides for creating one realtime response.
#derive(Debug, Eq)
pub(all) struct RealtimeResponseCreateOptions {
  modalities : Array[String]?
  instructions : String?
  metadata : Map[String, Json]?
}

///|
/// Construct realtime response overrides.
pub fn RealtimeResponseCreateOptions::new(
  modalities? : Array[String],
  instructions? : String,
  metadata? : Map[String, Json],
) -> RealtimeResponseCreateOptions {
  { modalities, instructions, metadata, }
}

///|
/// Normalized event sent from a client to a realtime model.
#derive(Debug, Eq)
pub(all) enum RealtimeClientEvent {
  RealtimeSessionUpdate(RealtimeSessionConfig)
  RealtimeInputAudioAppend(String)
  RealtimeInputAudioCommit
  RealtimeInputAudioClear
  RealtimeConversationItemCreate(RealtimeConversationItem)
  RealtimeConversationItemTruncate(
    item_id~ : String,
    content_index~ : Int32,
    audio_end_ms~ : Int32
  )
  RealtimeResponseCreate(RealtimeResponseCreateOptions?)
  RealtimeResponseCancel
}

///|
/// Normalized event emitted by a realtime model. Every variant retains the
/// original provider event in `raw`.
#derive(Debug, Eq)
pub(all) enum RealtimeServerEvent {
  RealtimeSessionCreated(session_id~ : String?, raw~ : Json)
  RealtimeSessionUpdated(raw~ : Json)
  RealtimeSpeechStarted(item_id~ : String?, raw~ : Json)
  RealtimeSpeechStopped(item_id~ : String?, raw~ : Json)
  RealtimeAudioCommitted(
    item_id~ : String?,
    previous_item_id~ : String?,
    raw~ : Json
  )
  RealtimeConversationItemAdded(item_id~ : String, item~ : Json, raw~ : Json)
  RealtimeInputTranscriptionCompleted(
    item_id~ : String,
    transcript~ : String,
    raw~ : Json
  )
  RealtimeResponseCreated(response_id~ : String, raw~ : Json)
  RealtimeResponseDone(response_id~ : String, status~ : String, raw~ : Json)
  RealtimeOutputItemAdded(response_id~ : String, item_id~ : String, raw~ : Json)
  RealtimeOutputItemDone(response_id~ : String, item_id~ : String, raw~ : Json)
  RealtimeContentPartAdded(
    response_id~ : String,
    item_id~ : String,
    raw~ : Json
  )
  RealtimeContentPartDone(response_id~ : String, item_id~ : String, raw~ : Json)
  RealtimeAudioDelta(
    response_id~ : String,
    item_id~ : String,
    delta~ : String,
    raw~ : Json
  )
  RealtimeAudioDone(response_id~ : String, item_id~ : String, raw~ : Json)
  RealtimeAudioTranscriptDelta(
    response_id~ : String,
    item_id~ : String,
    delta~ : String,
    raw~ : Json
  )
  RealtimeAudioTranscriptDone(
    response_id~ : String,
    item_id~ : String,
    transcript~ : String?,
    raw~ : Json
  )
  RealtimeTextDelta(
    response_id~ : String,
    item_id~ : String,
    delta~ : String,
    raw~ : Json
  )
  RealtimeTextDone(
    response_id~ : String,
    item_id~ : String,
    text~ : String?,
    raw~ : Json
  )
  RealtimeFunctionCallArgumentsDelta(
    response_id~ : String,
    item_id~ : String,
    call_id~ : String,
    delta~ : String,
    raw~ : Json
  )
  RealtimeFunctionCallArgumentsDone(
    response_id~ : String,
    item_id~ : String,
    call_id~ : String,
    name~ : String,
    arguments~ : String,
    raw~ : Json
  )
  RealtimeError(message~ : String, code~ : String?, raw~ : Json)
  RealtimeCustom(raw_type~ : String, raw~ : Json)
}

///|
/// Options for requesting a short-lived realtime client secret.
#derive(Debug, Eq)
pub(all) struct RealtimeClientSecretOptions {
  expires_after_seconds : Int32?
  session_config : RealtimeSessionConfig?
}

///|
/// Construct realtime client-secret options.
pub fn RealtimeClientSecretOptions::new(
  expires_after_seconds? : Int32,
  session_config? : RealtimeSessionConfig,
) -> RealtimeClientSecretOptions {
  { expires_after_seconds, session_config, }
}

///|
/// Short-lived authentication material returned by a realtime provider.
#derive(Debug, Eq)
pub(all) struct RealtimeClientSecretResult {
  token : String
  url : String
  expires_at : Int32?
}

///|
/// Construct a realtime client-secret result.
pub fn RealtimeClientSecretResult::new(
  token~ : String,
  url~ : String,
  expires_at? : Int32,
) -> RealtimeClientSecretResult {
  { token, url, expires_at, }
}

///|
/// WebSocket endpoint and provider-specific subprotocols for a client.
#derive(Debug, Eq)
pub(all) struct RealtimeWebSocketConfig {
  url : String
  protocols : Array[String]
}

///|
/// Construct a realtime WebSocket configuration.
pub fn RealtimeWebSocketConfig::new(
  url~ : String,
  protocols? : Array[String] = [],
) -> RealtimeWebSocketConfig {
  { url, protocols, }
}

///|
/// Options accepted by a provider-level realtime factory token helper.
#derive(Debug, Eq)
pub(all) struct RealtimeFactoryTokenOptions {
  model : String
  expires_after_seconds : Int32?
  session_config : RealtimeSessionConfig?
}

///|
/// Construct provider-level realtime token options.
pub fn RealtimeFactoryTokenOptions::new(
  model~ : String,
  expires_after_seconds? : Int32,
  session_config? : RealtimeSessionConfig,
) -> RealtimeFactoryTokenOptions {
  { model, expires_after_seconds, session_config, }
}

///|
pub extend RealtimeOutputModality with Debug::{to_repr}

///|
pub extend RealtimeOutputModality with Eq::{not_equal, equal}

///|
pub extend RealtimeAudioTranscriptionConfig with Debug::{to_repr}

///|
pub extend RealtimeAudioTranscriptionConfig with Eq::{not_equal, equal}

///|
pub extend RealtimeTurnDetection with Debug::{to_repr}

///|
pub extend RealtimeTurnDetection with Eq::{not_equal, equal}

///|
pub extend RealtimeToolDefinition with Debug::{to_repr}

///|
pub extend RealtimeToolDefinition with Eq::{not_equal, equal}

///|
pub extend RealtimeSessionConfig with Debug::{to_repr}

///|
pub extend RealtimeSessionConfig with Eq::{not_equal, equal}

///|
pub extend RealtimeConversationItem with Debug::{to_repr}

///|
pub extend RealtimeConversationItem with Eq::{not_equal, equal}

///|
pub extend RealtimeResponseCreateOptions with Debug::{to_repr}

///|
pub extend RealtimeResponseCreateOptions with Eq::{not_equal, equal}

///|
pub extend RealtimeClientEvent with Debug::{to_repr}

///|
pub extend RealtimeClientEvent with Eq::{not_equal, equal}

///|
pub extend RealtimeServerEvent with Debug::{to_repr}

///|
pub extend RealtimeServerEvent with Eq::{not_equal, equal}

///|
pub extend RealtimeClientSecretOptions with Debug::{to_repr}

///|
pub extend RealtimeClientSecretOptions with Eq::{not_equal, equal}

///|
pub extend RealtimeClientSecretResult with Debug::{to_repr}

///|
pub extend RealtimeClientSecretResult with Eq::{not_equal, equal}

///|
pub extend RealtimeWebSocketConfig with Debug::{to_repr}

///|
pub extend RealtimeWebSocketConfig with Eq::{not_equal, equal}

///|
pub extend RealtimeFactoryTokenOptions with Debug::{to_repr}

///|
pub extend RealtimeFactoryTokenOptions with Eq::{not_equal, equal}
