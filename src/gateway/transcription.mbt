///|
/// The AI Gateway transcription model: POST /transcription-model with the
/// audio inline as Base64; the transcript comes back as JSON.
struct GatewayTranscriptionModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int32
  http_transport : &@provider_utils.HttpTransport
}

///|
fn gateway_transcription_value(
  model_id : String,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int32,
  http_transport~ : &@provider_utils.HttpTransport,
) -> GatewayTranscriptionModel {
  {
    provider_name: "gateway.transcription",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn GatewayTranscriptionModel::transcription_headers(
  self : GatewayTranscriptionModel,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let resolved = gateway_base_headers(
    api_key=self.api_key,
    headers=self.headers,
    extra~,
    content_type="application/json",
    accept="application/json",
  )
  resolved["ai-transcription-model-specification-version"] = "4"
  resolved["ai-model-id"] = self.model_id
  resolved
}

///|
/// Decode the transcription response: text plus optional segments,
/// language, and duration.
fn gateway_decode_transcription_response(
  value : Json,
) -> (String, Array[@provider.TranscriptionSegment], String?, Double?) raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match value {
    { "text": String(text), .. } => {
      let segments : Array[@provider.TranscriptionSegment] = []
      match value {
        { "segments": Array(items), .. } =>
          for item in items {
            match item {
              {
                "text": String(segment_text),
                "startSecond": Number(start, ..),
                "endSecond": Number(end, ..),
                ..
              } =>
                segments.push(
                  @provider.TranscriptionSegment::new(
                    text=segment_text,
                    start_second=start,
                    end_second=end,
                  ),
                )
              _ => ()
            }
          }
        _ => ()
      }
      let language = match value {
        { "language": String(language), .. } => Some(language)
        _ => None
      }
      let duration = match value {
        { "durationInSeconds": Number(seconds, ..), .. } => Some(seconds)
        _ => None
      }
      (text, segments, language, duration)
    }
    _ => fail("gateway transcription response missing text")
  }
}

///|
pub impl @provider.TranscriptionModelV4 for GatewayTranscriptionModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.TranscriptionModelV4 for GatewayTranscriptionModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.TranscriptionModelV4 for GatewayTranscriptionModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.TranscriptionModelV4 for GatewayTranscriptionModel with fn do_generate(
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
  let audio = @provider_utils.resolve_transcription_audio(options.audio)
  let fields : Map[String, Json] = Map([
    ("audio", Json::string(@base64.encode(audio, padding=true))),
    ("mediaType", Json::string(options.media_type)),
  ])
  if resolution.values.length() > 0 {
    fields["providerOptions"] = Json::object(resolution.values)
  }
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/transcription-model"),
    headers=self.transcription_headers(extra=options.headers),
    body=Json::object(fields),
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=gateway_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let (text, segments, language, duration) = @provider_utils.handle_json_response(
    response, gateway_decode_transcription_response,
  )
  @provider.TranscriptionModelV4Result::new(
    text~,
    segments~,
    language?,
    duration_in_seconds?=duration,
    warnings~,
    request=response.request,
    response=response.response,
  )
}

///|
pub impl @provider.TranscriptionModelV4 for GatewayTranscriptionModel with fn do_stream(
  _self,
  _options,
  _on_event,
) -> @provider.TranscriptionModelV4StreamResult raise {
  raise @provider.UnsupportedFunctionalityError(
    functionality="gateway transcription realtime streaming",
  )
}
