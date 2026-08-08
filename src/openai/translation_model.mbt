///|
/// Model identifier accepted by the OpenAI Realtime translation API.
pub type OpenAITranslationModelId = String

///|
/// Provider options accepted by OpenAI Realtime translation.
///
/// The upstream API currently exposes an empty options schema. Keeping the
/// type public gives callers a stable extension point when OpenAI adds fields.
pub(all) struct OpenAITranslationModelOptions {} derive(Debug, Eq)

///|
/// Construct the current empty OpenAI translation options value.
pub fn OpenAITranslationModelOptions::new() -> OpenAITranslationModelOptions {
  OpenAITranslationModelOptions::{  }
}

///|
/// Convert translation options to the OpenAI provider namespace.
pub fn OpenAITranslationModelOptions::to_provider_options(
  _self : OpenAITranslationModelOptions,
  provider_name? : String = "openai",
) -> Map[String, Json] {
  openai_typed_namespace(provider_name, Map([]))
}

///|
/// Official OpenAI Realtime speech translation model.
pub struct OpenAITranslationModel {
  priv provider_name : String
  priv base_url : String
  priv model_id : OpenAITranslationModelId
  priv api_key : String
  priv headers : Map[String, String]
  priv websocket_connector : &@provider_utils.WebSocketConnector
}

///|
priv struct OpenAITranslationStreamResult {
  request : @provider.RequestMetadata?
  response : @provider.ResponseMetadata?
}

///|
fn openai_translation_model(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : OpenAITranslationModelId,
  api_key~ : String,
  headers~ : Map[String, String],
  websocket_connector~ : &@provider_utils.WebSocketConnector,
) -> OpenAITranslationModel {
  {
    provider_name: "\{provider_name}.translation",
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
    api_key,
    headers: @provider_utils.copy_headers(headers),
    websocket_connector,
  }
}

///|
/// Return the provider-qualified translation model name.
pub fn OpenAITranslationModel::provider(
  self : OpenAITranslationModel,
) -> String {
  self.provider_name
}

///|
/// Return the provider model identifier.
pub fn OpenAITranslationModel::model_id(
  self : OpenAITranslationModel,
) -> String {
  self.model_id
}

///|
priv struct OpenAIRealtimeConnectionOptions {
  protocols : Array[String]
  headers : Map[String, String]
}

///|
fn openai_realtime_connection_options(
  headers : Map[String, String],
) -> OpenAIRealtimeConnectionOptions {
  let handshake_headers : Map[String, String] = Map([])
  let mut bearer_token : String? = None
  for entry in headers.iter2() {
    let (key, value) = entry
    if key.to_lower() == "authorization" {
      let trimmed = value.trim().to_owned()
      if trimmed.to_lower().has_prefix("bearer ") {
        let token = trimmed[7:].trim().to_owned()
        if token != "" {
          bearer_token = Some(token)
        }
      }
    } else {
      handshake_headers[key] = value
    }
  }
  match bearer_token {
    Some(token) =>
      {
        protocols: ["realtime", "openai-insecure-api-key.\{token}"],
        headers: handshake_headers,
      }
    None =>
      {
        protocols: ["realtime"],
        headers: @provider_utils.copy_headers(headers),
      }
  }
}

///|
fn OpenAITranslationModel::url(self : OpenAITranslationModel) -> String {
  @provider_utils.to_websocket_url(
    @provider_utils.append_query(
      @provider_utils.append_path(self.base_url, "/realtime/translations"),
      { "model": self.model_id },
    ),
  )
}

///|
fn OpenAITranslationModel::request_headers(
  self : OpenAITranslationModel,
  call_headers : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      ["moonai/openai/\{VERSION}"],
    ),
    call_headers,
  )
}

///|
fn openai_translation_session(target_language : String) -> Json {
  {
    "type": "session.update",
    "session": {
      "audio": {
        "input": {
          "transcription": { "model": "gpt-realtime-whisper" },
          "noise_reduction": Json::null(),
        },
        "output": { "language": target_language },
      },
    },
  }
}

///|
fn openai_translation_warnings(
  call_options : @provider.SpeechTranslationModelV4StreamOptions,
  _provider_name : String,
) -> Array[@provider.Warning] {
  let resolution = resolve_official_openai_provider_options(
    call_options.provider_options,
  )
  let reader = @provider_utils.ProviderOptionsReader::new(
    resolution,
    path="providerOptions.openai",
  )
  let warnings = reader.diagnostics()
  if call_options.source_language is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="sourceLanguage",
        details="The OpenAI Realtime translation API auto-detects the source language and does not accept a source language.",
      ),
    )
  }
  if call_options.output_audio_format is Some(_) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="outputAudioFormat",
        details="The OpenAI Realtime translation API always outputs 24kHz 16-bit PCM audio and does not accept an output audio format.",
      ),
    )
  }
  warnings
}

///|
fn OpenAITranslationModel::validate_openai_translation_options(
  self : OpenAITranslationModel,
  call_options : @provider.SpeechTranslationModelV4StreamOptions,
) -> Unit raise {
  guard call_options.target_language.trim() != "" else {
    fail("targetLanguage is required for translation model '\{self.model_id}'.")
  }
  let input_format = call_options.input_audio_format
  guard input_format.media_type == "audio/pcm" &&
    (
      input_format.sample_rate is None ||
      input_format.sample_rate is Some(24000)
    ) else {
    fail(
      "The OpenAI Realtime translation API only supports 24kHz 16-bit PCM input audio.",
    )
  }
}

///|
async fn send_openai_translation_audio(
  connection : &@provider_utils.WebSocketConnection,
  audio : &@provider.AudioStream,
  cancellation_token : @provider.CancellationToken?,
) -> Unit {
  for ;; {
    @provider.check_cancellation(cancellation_token)
    match audio.read_next() {
      Some(chunk) => {
        let encoded = match chunk {
          @provider.AudioBytes(data) =>
            @provider_utils.convert_bytes_to_base64(data)
          @provider.AudioBase64(data) => data
        }
        connection.send_text(
          (
            { "type": "session.input_audio_buffer.append", "audio": encoded } :
            Json).stringify(),
        )
      }
      None => break
    }
  }
  @provider.check_cancellation(cancellation_token)
  connection.send_text(({ "type": "session.close" } : Json).stringify())
}

///|
fn openai_translation_close_error(code : Int?, reason : String?) -> String {
  let code_text = match code {
    Some(value) => value.to_string()
    None => "unknown"
  }
  let reason_text = match reason {
    Some(value) if value != "" => ", reason: \{value}"
    _ => ""
  }
  "OpenAI realtime translation WebSocket closed unexpectedly before finishing (code \{code_text}\{reason_text})."
}

///|
async fn OpenAITranslationModel::stream_translation_v4(
  self : OpenAITranslationModel,
  call_options : @provider.SpeechTranslationModelV4StreamOptions,
  on_event : async (@provider.SpeechTranslationModelV4StreamPart) -> Unit,
) -> OpenAITranslationStreamResult {
  let request_created_at = (@env.now() / 1000UL).to_int()
  self.validate_openai_translation_options(call_options)
  @provider.check_cancellation(call_options.cancellation_token)
  let warnings = openai_translation_warnings(call_options, self.provider_name)
  let session_update = openai_translation_session(call_options.target_language)
  let url = self.url()
  let realtime = openai_realtime_connection_options(
    self.request_headers(call_options.headers),
  )
  defer call_options.audio.cancel()
  let connection = self.websocket_connector.connect(
    url,
    realtime.protocols,
    realtime.headers,
  )
  defer connection.close()
  on_event(@provider.SpeechTranslationV4StreamStart(warnings~))
  connection.send_text(session_update.stringify())
  let source_text = StringBuilder::new()
  let output_text = StringBuilder::new()
  @async.with_task_group() <| group => {
    let sender = group.spawn(no_wait=true) <| () => {
      send_openai_translation_audio(
        connection,
        call_options.audio,
        call_options.cancellation_token,
      )
    }
    match call_options.cancellation_token {
      Some(token) =>
        group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
          while !token.is_cancelled() {
            @async.sleep(20)
          }
          connection.close()
        }
      None => ()
    }
    let mut finished = false
    while !finished {
      let received = connection.receive()
      let text = match received {
        @provider_utils.WebSocketText(value) => Some(value)
        @provider_utils.WebSocketBinary(value) => Some(@utf8.decode(value))
        @provider_utils.WebSocketClosed(code~, reason~) => {
          @provider.check_cancellation(call_options.cancellation_token)
          fail(openai_translation_close_error(code, reason))
        }
      }
      match text {
        None => ()
        Some(value) => {
          let raw : Json? = Some(@json.parse(value)) catch { _ => None }
          match raw {
            None => ()
            Some(event) => {
              if call_options.include_raw_chunks {
                on_event(@provider.SpeechTranslationV4Raw(event))
              }
              let event_type = @provider_utils.json_string_field(event, "type")
              match event_type {
                Some("session.output_audio.delta") =>
                  match @provider_utils.json_string_field(event, "delta") {
                    Some(delta) if delta != "" =>
                      on_event(
                        @provider.SpeechTranslationV4Audio(
                          id=None,
                          audio=@provider.SpeechAudioData::base64(delta),
                          provider_metadata=Map([]),
                        ),
                      )
                    _ => ()
                  }
                Some("session.output_transcript.delta") => {
                  let delta = @provider_utils.json_string_field(event, "delta").unwrap_or(
                    "",
                  )
                  output_text.write_string(delta)
                  on_event(
                    @provider.SpeechTranslationV4OutputTextDelta(
                      id=None,
                      delta~,
                      provider_metadata=Map([]),
                    ),
                  )
                }
                Some("session.input_transcript.delta") => {
                  let delta = @provider_utils.json_string_field(event, "delta").unwrap_or(
                    "",
                  )
                  source_text.write_string(delta)
                  on_event(
                    @provider.SpeechTranslationV4SourceTranscriptDelta(
                      id=None,
                      delta~,
                      provider_metadata=Map([]),
                    ),
                  )
                }
                Some("session.closed") => finished = true
                Some("error") =>
                  on_event(
                    @provider.SpeechTranslationV4Error(
                      openai_error_message(event).unwrap_or(
                        "OpenAI realtime error",
                      ),
                    ),
                  )
                _ => ()
              }
            }
          }
        }
      }
    }
    sender.cancel()
  }
  let final_source_text = source_text.to_string()
  let final_output_text = output_text.to_string()
  if final_source_text != "" {
    on_event(
      @provider.SpeechTranslationV4SourceTranscriptFinal(
        id=None,
        text=final_source_text,
        start_second=None,
        end_second=None,
        channel_index=None,
        provider_metadata=Map([]),
      ),
    )
  }
  if final_output_text != "" {
    on_event(
      @provider.SpeechTranslationV4OutputTextFinal(
        id=None,
        text=final_output_text,
        provider_metadata=Map([]),
      ),
    )
  }
  on_event(
    @provider.SpeechTranslationV4Finish(
      source_text=final_source_text,
      output_text=final_output_text,
      duration_in_seconds=None,
      usage=None,
      provider_metadata=Map([]),
    ),
  )
  {
    request: Some(
      @provider.RequestMetadata::new(
        url~,
        headers=realtime.headers,
        body=session_update.stringify(),
      ),
    ),
    response: Some(
      @provider.ResponseMetadata::new(
        model_id=self.model_id,
        created_at=request_created_at,
      ),
    ),
  }
}

///|
pub impl @provider.SpeechTranslationModelV4 for OpenAITranslationModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.SpeechTranslationModelV4 for OpenAITranslationModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.SpeechTranslationModelV4 for OpenAITranslationModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.SpeechTranslationModelV4 for OpenAITranslationModel with fn do_stream(
  self,
  options,
  on_part,
) {
  let response = self.stream_translation_v4(options, on_part)
  @provider.SpeechTranslationModelV4StreamResult::new(
    request?=response.request,
    response?=response.response,
  )
}
