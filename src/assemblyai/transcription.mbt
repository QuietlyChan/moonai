///|
/// The AssemblyAI transcription model: upload audio, submit a transcript
/// job, then poll until completed/error.
struct AssemblyAITranscriptionModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  poll_interval_ms : Int
  poll_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
/// Default polling interval for transcript status checks.
pub const ASSEMBLYAI_POLL_INTERVAL_MS : Int = 3000

///|
/// Default maximum time to wait for a transcript to finish.
pub const ASSEMBLYAI_POLL_TIMEOUT_MS : Int = 600_000

///|
fn assemblyai_transcription_value(
  model_id : AssemblyAITranscriptionModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  poll_interval_ms~ : Int,
  poll_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> AssemblyAITranscriptionModel {
  {
    provider_name: "assemblyai.transcription",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    poll_interval_ms,
    poll_timeout_ms,
    http_transport,
  }
}

///|
fn AssemblyAITranscriptionModel::request_headers(
  self : AssemblyAITranscriptionModel,
  extra~ : Map[String, String],
  content_type? : String,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="ASSEMBLYAI_API_KEY",
    description="AssemblyAI",
  )
  let base : Map[String, String] = Map([("Authorization", api_key)])
  if content_type is Some(value) {
    base["Content-Type"] = value
  }
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(base, self.headers),
      extra,
    ),
    ["ai-sdk/\{self.provider_name}/\{VERSION}"],
  )
}

///|
fn assemblyai_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "error": String(message), .. } => Some(message)
    { "error": { "message": String(message), .. }, .. } => Some(message)
    { "message": String(message), .. } => Some(message)
    _ => None
  }
}

///|
pub impl @provider.TranscriptionModelV4 for AssemblyAITranscriptionModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.TranscriptionModelV4 for AssemblyAITranscriptionModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.TranscriptionModelV4 for AssemblyAITranscriptionModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.TranscriptionModelV4 for AssemblyAITranscriptionModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["assemblyai"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let cancellation_token = options.cancellation_token
  let audio = @provider_utils.resolve_transcription_audio(options.audio)
  // 1. Upload the raw audio bytes; the response carries a hosted URL.
  let upload_response = @provider_utils.post_bytes(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/v2/upload"),
    headers=self.request_headers(
      extra=options.headers,
      content_type="application/octet-stream",
    ),
    body=audio,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=assemblyai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let upload_url = match upload_response.value {
    { "upload_url": String(url), .. } => url
    _ => fail("assemblyai upload response missing upload_url")
  }
  // 2. Submit the transcription job.
  let fields : Map[String, Json] = Map([
    ("audio_url", Json::string(upload_url)),
    ("speech_model", Json::string(self.model_id)),
  ])
  match resolution.values.get("language_code") {
    Some(String(value)) => fields["language_code"] = Json::string(value)
    _ => ()
  }
  if resolution.values.get("format_text") is Some(value) {
    fields["format_text"] = value
  }
  if resolution.values.get("punctuate") is Some(value) {
    fields["punctuate"] = value
  }
  let submit_response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/v2/transcript"),
    headers=self.request_headers(
      extra=options.headers,
      content_type="application/json",
    ),
    body=Json::object(fields),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=assemblyai_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let transcript_id = match submit_response.value {
    { "id": String(id), .. } => id
    _ => fail("assemblyai transcript response missing id")
  }
  // 3. Poll until the transcript leaves queued/processing.
  let poll_started_at = @env.now()
  for ;; {
    @provider.check_cancellation(cancellation_token)
    @provider_utils.sleep_with_cancellation(
      self.poll_interval_ms,
      cancellation_token,
    )
    if @env.now() - poll_started_at > self.poll_timeout_ms.to_uint64() {
      fail(
        "assemblyai transcription polling exceeded \{self.poll_timeout_ms}ms",
      )
    }
    let poll_response = @provider_utils.get_json(
      provider_name=self.provider_name,
      url=@provider_utils.append_path(
        self.base_url,
        "/v2/transcript/\{transcript_id}",
      ),
      headers=self.request_headers(extra=options.headers),
      timeout_ms=self.idle_timeout_ms,
      retry_policy=options.retry_policy,
      cancellation_token?,
      error_to_message=assemblyai_error_to_message,
      is_retryable_response=(_status_code, _error) => None,
      transport=self.http_transport,
    )
    match poll_response.value {
      { "status": "completed", "text": String(text), .. } => {
        let language = match poll_response.value {
          { "language_code": String(code), .. } => Some(code)
          _ => None
        }
        return @provider.TranscriptionModelV4Result::new(
          text~,
          language?,
          warnings~,
          request=submit_response.request,
          response=poll_response.response,
        )
      }
      { "status": "error", .. } => {
        let message = match poll_response.value {
          { "error": String(error), .. } => error
          _ => "assemblyai transcription failed"
        }
        fail(message)
      }
      _ => continue
    }
  }
}

///|
pub impl @provider.TranscriptionModelV4 for AssemblyAITranscriptionModel with fn do_stream(
  _self,
  _options,
  _on_event,
) -> @provider.TranscriptionModelV4StreamResult raise {
  raise @provider.UnsupportedFunctionalityError(
    functionality="AssemblyAI realtime streaming",
  )
}
