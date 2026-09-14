///|
/// The AI Gateway speech model: POST /speech-model; the reply carries the
/// generated audio as a Base64 string.
struct GatewaySpeechModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn gateway_speech_value(
  model_id : String,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> GatewaySpeechModel {
  {
    provider_name: "gateway",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn GatewaySpeechModel::speech_headers(
  self : GatewaySpeechModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let resolved = gateway_base_headers(
    api_key=self.api_key,
    headers=self.headers,
    extra~,
    content_type="application/json",
    accept="application/json",
  )
  resolved["ai-speech-model-specification-version"] = "4"
  resolved["ai-model-id"] = self.model_id
  resolved
}

///|
/// Decode the speech response: Base64 audio plus server warnings.
fn gateway_decode_speech_response(value : Json) -> String raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match value {
    { "audio": String(audio), .. } => audio
    _ => fail("gateway speech response missing audio")
  }
}

///|
pub impl @provider.SpeechModelV4 for GatewaySpeechModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.SpeechModelV4 for GatewaySpeechModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.SpeechModelV4 for GatewaySpeechModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.SpeechModelV4 for GatewaySpeechModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let fields : Map[String, Json] = Map([("text", Json::string(options.text))])
  if options.voice is Some(value) {
    fields["voice"] = Json::string(value)
  }
  if options.output_format is Some(value) {
    fields["outputFormat"] = Json::string(value)
  }
  if options.instructions is Some(value) {
    fields["instructions"] = Json::string(value)
  }
  if options.speed is Some(value) {
    fields["speed"] = Json::number(value)
  }
  if options.language is Some(value) {
    fields["language"] = Json::string(value)
  }
  if resolution.values.length() > 0 {
    fields["providerOptions"] = Json::object(resolution.values)
  }
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/speech-model"),
    headers=self.speech_headers(extra=options.headers),
    body=Json::object(fields),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=gateway_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let audio = @provider_utils.handle_json_response(
    response, gateway_decode_speech_response,
  )
  @provider.SpeechModelV4Result::new(
    audio=@provider.SpeechAudioData::base64(audio),
    warnings~,
    request=response.request,
    response={
      ..response.response,
      model_id: Some(self.model_id),
      body: Some(response.value.stringify()),
    },
    provider_metadata=@provider_utils.provider_metadata_from_json(
      response.value,
      self.provider_name,
    ),
  )
}
