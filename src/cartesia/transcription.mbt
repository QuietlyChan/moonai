///|
/// The Cartesia transcription model: multipart POST /stt/transcribe.
struct CartesiaTranscriptionModel {
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
fn cartesia_transcription_value(
  model_id : CartesiaTranscriptionModelId,
  api_key~ : String,
  base_url~ : String,
  api_version~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> CartesiaTranscriptionModel {
  {
    provider_name: "cartesia.transcription",
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
fn decode_cartesia_transcription(value : Json) -> String raise {
  match value {
    { "text": String(text), .. } => text
    _ => fail("cartesia transcription response missing text")
  }
}

///|
pub impl @provider.TranscriptionModelV4 for CartesiaTranscriptionModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.TranscriptionModelV4 for CartesiaTranscriptionModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.TranscriptionModelV4 for CartesiaTranscriptionModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.TranscriptionModelV4 for CartesiaTranscriptionModel with fn do_generate(
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
  let audio = @provider_utils.resolve_transcription_audio(options.audio)
  let cancellation_token = options.cancellation_token
  let fields : Array[@provider_utils.MultipartField] = [
    @provider_utils.MultipartField::file(
      name="file",
      filename="audio",
      media_type=options.media_type,
      data=audio,
    ),
    @provider_utils.MultipartField::text(name="model_id", value=self.model_id),
    @provider_utils.MultipartField::text(
      name="language",
      value=match resolution.values.get("language") {
        Some(String(value)) => value
        _ => "en"
      },
    ),
  ]
  let form_data = @provider_utils.encode_multipart_form_data(fields)
  let response = @provider_utils.post_multipart(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/stt/transcribe"),
    headers=self.request_headers(extra=options.headers),
    form_data~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=cartesia_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let text = @provider_utils.handle_json_response(
    response, decode_cartesia_transcription,
  )
  @provider.TranscriptionModelV4Result::new(text~, warnings~)
}

///|
pub impl @provider.TranscriptionModelV4 for CartesiaTranscriptionModel with fn do_stream(
  _self,
  _options,
  _on_event,
) -> @provider.TranscriptionModelV4StreamResult raise {
  raise @provider.UnsupportedFunctionalityError(
    functionality="Cartesia transcription streaming",
  )
}

///|
fn CartesiaTranscriptionModel::request_headers(
  self : CartesiaTranscriptionModel,
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
          ("Cartesia-Version", self.api_version),
        ]),
        self.headers,
      ),
      extra,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
}
