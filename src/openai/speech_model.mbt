///|
/// Official OpenAI text-to-speech model.
priv struct OpenAISpeechModel {
  provider_name : String
  base_url : String
  model_id : String
  api_key : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
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
  call_headers : Map[String, String],
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
    call_headers,
  )
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
  call_options : @provider.SpeechModelV4CallOptions,
  _provider_name : String,
) -> (Json, String, Array[@provider.Warning]) {
  let resolution = resolve_official_openai_provider_options(
    call_options.provider_options,
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
async fn OpenAISpeechModel::generate_speech_v4(
  self : OpenAISpeechModel,
  call_options : @provider.SpeechModelV4CallOptions,
) -> @provider.SpeechModelV4Result {
  let request_created_at = (@env.now() / 1000UL).to_int()
  let (body, _format, warnings) = prepare_openai_speech_request(
    self.model_id,
    call_options,
    self.provider_name,
  )
  let cancellation_token = call_options.cancellation_token
  let response = @provider_utils.post_json_binary(
    provider_name=self.provider_name,
    url=self.url(),
    headers=self.request_headers(call_options.headers),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=call_options.retry_policy,
    cancellation_token?,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  let response_metadata = @provider.merge_response_metadata(
    Some(response.response),
    @provider.ResponseMetadata::new(
      model_id=self.model_id,
      created_at=request_created_at,
    ),
  )
  @provider.SpeechModelV4Result::new(
    audio=@provider.SpeechAudioData::bytes(response.value),
    warnings~,
    request=response.request,
    response=response_metadata,
  )
}

///|
impl @provider.SpeechModelV4 for OpenAISpeechModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.SpeechModelV4 for OpenAISpeechModel with fn provider(self) -> String {
  self.provider_name
}

///|
impl @provider.SpeechModelV4 for OpenAISpeechModel with fn model_id(self) -> String {
  self.model_id
}

///|
impl @provider.SpeechModelV4 for OpenAISpeechModel with fn do_generate(
  self,
  options,
) {
  self.generate_speech_v4(options)
}
