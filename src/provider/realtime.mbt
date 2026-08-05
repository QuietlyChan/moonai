///|
/// Output modality requested from a realtime model.
pub(all) enum RealtimeOutputModality {
  RealtimeText
  RealtimeAudio
} derive(Debug, Eq)

///|
/// Input or output transcription settings for a realtime session.
pub(all) struct RealtimeAudioTranscriptionConfig {
  model : String?
  language : String?
  prompt : String?
} derive(Debug, Eq)

///|
/// Construct realtime audio transcription settings.
pub fn RealtimeAudioTranscriptionConfig::new(
  model? : String,
  language? : String,
  prompt? : String,
) -> RealtimeAudioTranscriptionConfig {
  { model, language, prompt }
}

///|
/// Voice activity detection settings. `Disabled` represents push-to-talk.
pub(all) enum RealtimeTurnDetection {
  RealtimeTurnDetectionDisabled
  RealtimeServerVad(
    threshold~ : Double?,
    silence_duration_ms~ : Int?,
    prefix_padding_ms~ : Int?
  )
  RealtimeSemanticVad(
    threshold~ : Double?,
    silence_duration_ms~ : Int?,
    prefix_padding_ms~ : Int?
  )
} derive(Debug, Eq)

///|
/// Construct server-side voice activity detection settings.
pub fn RealtimeTurnDetection::server_vad(
  threshold? : Double,
  silence_duration_ms? : Int,
  prefix_padding_ms? : Int,
) -> RealtimeTurnDetection {
  RealtimeServerVad(threshold~, silence_duration_ms~, prefix_padding_ms~)
}

///|
/// Construct semantic voice activity detection settings.
pub fn RealtimeTurnDetection::semantic_vad(
  threshold? : Double,
  silence_duration_ms? : Int,
  prefix_padding_ms? : Int,
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
pub(all) struct RealtimeToolDefinition {
  name : String
  description : String?
  parameters : Json
} derive(Debug, Eq)

///|
/// Construct a realtime function tool definition.
pub fn RealtimeToolDefinition::new(
  name~ : String,
  parameters~ : Json,
  description? : String,
) -> RealtimeToolDefinition {
  { name, description, parameters }
}

///|
/// Provider-neutral realtime session configuration.
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
} derive(Debug, Eq)

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
pub(all) enum RealtimeConversationItem {
  RealtimeTextMessage(text~ : String)
  RealtimeAudioMessage(audio~ : String)
  RealtimeFunctionCallOutput(
    call_id~ : String,
    name~ : String?,
    output~ : String
  )
} derive(Debug, Eq)

///|
/// Optional overrides for creating one realtime response.
pub(all) struct RealtimeResponseCreateOptions {
  modalities : Array[String]?
  instructions : String?
  metadata : Map[String, Json]?
} derive(Debug, Eq)

///|
/// Construct realtime response overrides.
pub fn RealtimeResponseCreateOptions::new(
  modalities? : Array[String],
  instructions? : String,
  metadata? : Map[String, Json],
) -> RealtimeResponseCreateOptions {
  { modalities, instructions, metadata }
}

///|
/// Normalized event sent from a client to a realtime model.
pub(all) enum RealtimeClientEvent {
  RealtimeSessionUpdate(RealtimeSessionConfig)
  RealtimeInputAudioAppend(String)
  RealtimeInputAudioCommit
  RealtimeInputAudioClear
  RealtimeConversationItemCreate(RealtimeConversationItem)
  RealtimeConversationItemTruncate(
    item_id~ : String,
    content_index~ : Int,
    audio_end_ms~ : Int
  )
  RealtimeResponseCreate(RealtimeResponseCreateOptions?)
  RealtimeResponseCancel
} derive(Debug, Eq)

///|
/// Normalized event emitted by a realtime model. Every variant retains the
/// original provider event in `raw`.
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
} derive(Debug, Eq)

///|
/// Options for requesting a short-lived realtime client secret.
pub(all) struct RealtimeClientSecretOptions {
  expires_after_seconds : Int?
  session_config : RealtimeSessionConfig?
} derive(Debug, Eq)

///|
/// Construct realtime client-secret options.
pub fn RealtimeClientSecretOptions::new(
  expires_after_seconds? : Int,
  session_config? : RealtimeSessionConfig,
) -> RealtimeClientSecretOptions {
  { expires_after_seconds, session_config }
}

///|
/// Short-lived authentication material returned by a realtime provider.
pub(all) struct RealtimeClientSecretResult {
  token : String
  url : String
  expires_at : Int?
} derive(Debug, Eq)

///|
/// Construct a realtime client-secret result.
pub fn RealtimeClientSecretResult::new(
  token~ : String,
  url~ : String,
  expires_at? : Int,
) -> RealtimeClientSecretResult {
  { token, url, expires_at }
}

///|
/// WebSocket endpoint and provider-specific subprotocols for a client.
pub(all) struct RealtimeWebSocketConfig {
  url : String
  protocols : Array[String]
} derive(Debug, Eq)

///|
/// Construct a realtime WebSocket configuration.
pub fn RealtimeWebSocketConfig::new(
  url~ : String,
  protocols? : Array[String] = [],
) -> RealtimeWebSocketConfig {
  { url, protocols }
}

///|
/// Options accepted by a provider-level realtime factory token helper.
pub(all) struct RealtimeFactoryTokenOptions {
  model : String
  expires_after_seconds : Int?
  session_config : RealtimeSessionConfig?
} derive(Debug, Eq)

///|
/// Construct provider-level realtime token options.
pub fn RealtimeFactoryTokenOptions::new(
  model~ : String,
  expires_after_seconds? : Int,
  session_config? : RealtimeSessionConfig,
) -> RealtimeFactoryTokenOptions {
  { model, expires_after_seconds, session_config }
}
