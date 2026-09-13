///|
/// The ElevenLabs speech model: POST /v1/text-to-speech/{voice} returning
/// raw audio bytes, authenticated via the `xi-api-key` header.
struct ElevenLabsSpeechModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn elevenlabs_speech_value(
  model_id : ElevenLabsSpeechModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> ElevenLabsSpeechModel {
  {
    provider_name: "elevenlabs.speech",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn ElevenLabsSpeechModel::elevenlabs_request_headers(
  self : ElevenLabsSpeechModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="ELEVENLABS_API_KEY",
    description="ElevenLabs",
  )
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([("xi-api-key", api_key)]),
        self.headers,
      ),
      extra,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
}

///|
/// Build the text-to-speech request body.
fn elevenlabs_speech_request_body(
  model_id : String,
  text~ : String,
  language~ : String?,
  speed~ : Double?,
  provider_options~ : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = Map([
    ("text", Json::string(text)),
    ("model_id", Json::string(model_id)),
  ])
  if language is Some(value) {
    fields["language_code"] = Json::string(value)
  }
  if speed is Some(value) {
    let voice_settings : Map[String, Json] = Map([
      ("speed", Json::number(value)),
    ])
    fields["voice_settings"] = Json::object(voice_settings)
  }
  for entry in provider_options.iter2() {
    fields[entry.0] = entry.1
  }
  Json::object(fields)
}

///|
pub impl @provider.SpeechModelV4 for ElevenLabsSpeechModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.SpeechModelV4 for ElevenLabsSpeechModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.SpeechModelV4 for ElevenLabsSpeechModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.SpeechModelV4 for ElevenLabsSpeechModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["elevenlabs"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let voice = options.voice.unwrap_or("21m00Tcm4TlvDq8ikWAM")
  let output_format = options.output_format.unwrap_or("mp3_44100_128")
  let language = match resolution.values.get("language_code") {
    Some(String(value)) => Some(value)
    _ => options.language
  }
  let mut speed : Double? = None
  if options.speed is Some(value) {
    speed = Some(value)
  }
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json_binary(
    provider_name=self.provider_name,
    url="\{self.base_url}/v1/text-to-speech/\{voice}?output_format=\{output_format}",
    headers=self.elevenlabs_request_headers(extra=options.headers),
    body=elevenlabs_speech_request_body(
      self.model_id,
      text=options.text,
      language~,
      speed~,
      provider_options=resolution.values,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=elevenlabs_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  @provider.SpeechModelV4Result::new(
    audio=@provider.SpeechAudioData::bytes(response.value),
    warnings~,
    request=response.request,
    response=response.response,
  )
}

///|
fn elevenlabs_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "detail": { "message": String(message), .. }, .. } => Some(message)
    { "detail": String(message), .. } => Some(message)
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}
