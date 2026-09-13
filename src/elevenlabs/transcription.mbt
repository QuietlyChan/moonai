///|
/// The ElevenLabs transcription model: multipart POST /v1/speech-to-text
/// (scribe models) returning a JSON transcript.
struct ElevenLabsTranscriptionModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn elevenlabs_transcription_value(
  model_id : ElevenLabsTranscriptionModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> ElevenLabsTranscriptionModel {
  {
    provider_name: "elevenlabs.transcription",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn decode_elevenlabs_transcription(value : Json) -> (String, String?) raise {
  match value {
    { "text": String(text), .. } => {
      let language = match value {
        { "language_code": String(code), .. } => Some(code)
        _ => None
      }
      (text, language)
    }
    _ => fail("elevenlabs transcription response missing text")
  }
}

///|
pub impl @provider.TranscriptionModelV4 for ElevenLabsTranscriptionModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.TranscriptionModelV4 for ElevenLabsTranscriptionModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.TranscriptionModelV4 for ElevenLabsTranscriptionModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.TranscriptionModelV4 for ElevenLabsTranscriptionModel with fn do_generate(
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
  ]
  for entry in resolution.values.iter2() {
    if entry.1 is String(text) {
      fields.push(
        @provider_utils.MultipartField::text(name=entry.0, value=text),
      )
    }
  }
  let request_headers = @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([
          (
            "xi-api-key",
            @provider_utils.load_api_key(
              self.api_key,
              environment_variable_name="ELEVENLABS_API_KEY",
              description="ElevenLabs",
            ),
          ),
        ]),
        self.headers,
      ),
      options.headers,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
  let form_data = @provider_utils.encode_multipart_form_data(fields)
  let response = @provider_utils.post_multipart(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/v1/speech-to-text"),
    headers=request_headers,
    form_data~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=elevenlabs_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (text, language) = @provider_utils.handle_json_response(
    response, decode_elevenlabs_transcription,
  )
  @provider.TranscriptionModelV4Result::new(
    text~,
    language?,
    warnings~,
    request=response.request,
    response=response.response,
  )
}

///|
pub impl @provider.TranscriptionModelV4 for ElevenLabsTranscriptionModel with fn do_stream(
  _self,
  _options,
  _on_event,
) -> @provider.TranscriptionModelV4StreamResult raise {
  raise @provider.UnsupportedFunctionalityError(
    functionality="ElevenLabs transcription streaming",
  )
}
