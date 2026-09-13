///|
/// The Cartesia speech model: POST /tts/bytes returning raw audio bytes.
struct CartesiaSpeechModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  api_version : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn cartesia_speech_value(
  model_id : CartesiaSpeechModelId,
  api_key~ : String,
  base_url~ : String,
  api_version~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> CartesiaSpeechModel {
  {
    provider_name: "cartesia.speech",
    api_key,
    base_url,
    model_id,
    api_version,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn CartesiaSpeechModel::request_headers(
  self : CartesiaSpeechModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="CARTESIA_API_KEY",
    description="Cartesia",
  )
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([
          ("Authorization", "Bearer \{api_key}"),
          ("Content-Type", "application/json"),
          ("Cartesia-Version", self.api_version),
        ]),
        self.headers,
      ),
      extra,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
}

///|
/// Build the /tts/bytes request body.
fn cartesia_speech_request_body(
  model_id : String,
  text~ : String,
  voice~ : String,
  language~ : String?,
  speed~ : Double?,
  provider_options~ : Map[String, Json],
) -> Json {
  let voice_fields : Map[String, Json] = Map([("id", Json::string(voice))])
  let voice_controls : Map[String, Json] = Map([])
  if speed is Some(value) {
    voice_controls["speed"] = Json::string(value.to_string())
  }
  if voice_controls.length() > 0 {
    voice_fields["_controlled"] = Json::boolean(true)
    voice_fields["controls"] = Json::object(voice_controls)
  }
  let fields : Map[String, Json] = Map([
    ("model_id", Json::string(model_id)),
    ("transcript", Json::string(text)),
    ("voice", Json::object(voice_fields)),
    (
      "output_format",
      { "container": "raw", "encoding": "pcm_s16le", "sample_rate": 44100 },
    ),
  ])
  if language is Some(value) {
    fields["language"] = Json::string(value)
  }
  for entry in provider_options.iter2() {
    fields[entry.0] = entry.1
  }
  Json::object(fields)
}

///|
pub impl @provider.SpeechModelV4 for CartesiaSpeechModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.SpeechModelV4 for CartesiaSpeechModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.SpeechModelV4 for CartesiaSpeechModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.SpeechModelV4 for CartesiaSpeechModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["cartesia"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let language = match resolution.values.get("language") {
    Some(String(value)) => Some(value)
    _ => options.language
  }
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json_binary(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/tts/bytes"),
    headers=self.request_headers(extra=options.headers),
    body=cartesia_speech_request_body(
      self.model_id,
      text=options.text,
      voice=options.voice.unwrap_or("694f9389-aac1-45b6-b726-9d9369183238"),
      language~,
      speed=options.speed,
      provider_options=resolution.values,
    ),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=cartesia_error_to_message,
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
fn cartesia_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "message": String(message), .. } => Some(message)
    { "error": String(message), .. } => Some(message)
    _ => None
  }
}
