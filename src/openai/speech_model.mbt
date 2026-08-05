///|
/// Official OpenAI text-to-speech model.
pub struct OpenAISpeechModel {
  priv provider_name : String
  priv base_url : String
  priv model_id : String
  priv api_key : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
fn openai_speech_model(
  provider_name~ : String,
  base_url~ : String,
  model_id~ : String,
  api_key~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> OpenAISpeechModel {
  {
    provider_name: "\{provider_name}.speech",
    base_url: @provider_utils.without_trailing_slash(base_url),
    model_id,
    api_key,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn OpenAISpeechModel::url(self : OpenAISpeechModel) -> String {
  @provider_utils.append_path(self.base_url, "/audio/speech")
}

///|
fn OpenAISpeechModel::request_headers(
  self : OpenAISpeechModel,
  call_options : @provider.SpeechCallOptions,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([
    ("Content-Type", "application/json"),
    ("Accept-Encoding", "identity"),
  ])
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.merge_headers(
    @provider_utils.with_user_agent_suffix(
      @provider_utils.merge_headers(headers, self.headers),
      ["moonai/openai/\{VERSION}"],
    ),
    call_options.headers,
  )
}

///|
fn openai_speech_output_media_type(format : String) -> String {
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
fn openai_speech_supports_format(format : String) -> Bool {
  format == "mp3" ||
  format == "opus" ||
  format == "aac" ||
  format == "flac" ||
  format == "wav" ||
  format == "pcm"
}

///|
fn prepare_openai_speech_request(
  model_id : String,
  call_options : @provider.SpeechCallOptions,
  provider_name : String,
) -> (Json, String, Array[@provider.Warning]) {
  let resolution = @provider_utils.resolve_provider_options(
    call_options.provider_options,
    provider_name~,
    aliases=["openai"],
  )
  let reader = @provider_utils.ProviderOptionsReader::new(
    resolution,
    path="providerOptions.openai",
  )
  let provider_instructions = reader.take_string("instructions")
  let provider_speed = reader.take_double("speed", min=0.25, max=4.0)
  let provider_format = reader.take_string("response_format", allowed=[
    "mp3", "opus", "aac", "flac", "wav", "pcm",
  ])
  let warnings = reader.diagnostics()
  let requested_format = match call_options.output_format {
    Some(value) => value
    None => provider_format.unwrap_or("mp3")
  }
  let format = if openai_speech_supports_format(requested_format) {
    requested_format
  } else {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="outputFormat",
        details="Unsupported output format: \{requested_format}. Using mp3 instead.",
      ),
    )
    "mp3"
  }
  if call_options.language is Some(language) {
    warnings.push(
      @provider.Warning::Unsupported(
        feature="language",
        details="OpenAI speech models do not support language selection. Language parameter \"\{language}\" was ignored.",
      ),
    )
  }
  let fields : Map[String, Json] = Map([
    ("model", Json::string(model_id)),
    ("input", Json::string(call_options.text)),
    ("voice", Json::string(call_options.voice.unwrap_or("alloy"))),
    ("response_format", Json::string(format)),
  ])
  let speed = match call_options.speed {
    Some(value) => Some(value)
    None => provider_speed
  }
  if speed is Some(value) {
    fields["speed"] = Json::number(value)
  }
  let instructions = match call_options.instructions {
    Some(value) => Some(value)
    None => provider_instructions
  }
  if instructions is Some(value) {
    fields["instructions"] = Json::string(value)
  }
  (Json::object(fields), format, warnings)
}

///|
async fn OpenAISpeechModel::generate_speech(
  self : OpenAISpeechModel,
  call_options : @provider.SpeechCallOptions,
) -> @provider.SpeechResponse {
  let (body, format, warnings) = prepare_openai_speech_request(
    self.model_id,
    call_options,
    self.provider_name,
  )
  let cancellation_token = call_options.cancellation_token
  let response = @provider_utils.post_json_binary(
    provider_name=self.provider_name,
    url=self.url(),
    headers=self.request_headers(call_options),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=call_options.retry_policy,
    cancellation_token?,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  @provider.SpeechResponse::new(
    audio=@provider.SpeechAudioData::bytes(response.value),
    media_type=openai_speech_output_media_type(format),
  )
  .with_diagnostics(
    None,
    Some(@provider.ResponseMetadata::new(model_id=self.model_id)),
    Map([]),
    warnings,
  )
  .with_transport(response.request, response.response)
}

///|
pub impl @provider.SpeechWireModel for OpenAISpeechModel with fn provider(
  self : OpenAISpeechModel,
) -> String {
  self.provider_name
}

///|
pub impl @provider.SpeechWireModel for OpenAISpeechModel with fn model_id(
  self : OpenAISpeechModel,
) -> String {
  self.model_id
}

///|
pub impl @provider.SpeechWireModel for OpenAISpeechModel with fn generate(
  self : OpenAISpeechModel,
  call_options : @provider.SpeechCallOptions,
) -> @provider.SpeechResponse {
  self.generate_speech(call_options)
}

///|
pub impl @provider.SpeechModelV4 for OpenAISpeechModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.SpeechModelV4 for OpenAISpeechModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.SpeechModelV4 for OpenAISpeechModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.SpeechModelV4 for OpenAISpeechModel with fn do_generate(
  self,
  options,
) {
  @provider.SpeechModelV4Result::from_speech_response(
    self.generate_speech(options.to_speech_call_options()),
  )
}
