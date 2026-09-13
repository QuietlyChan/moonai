///|
/// The Prodia language model: job-based text+image generation. The prompt is
/// submitted as a multipart job (optionally with an input image from the
/// last user file part); the multipart response carries the job result, the
/// assistant text (output .txt) and any generated images (image/* parts).
struct ProdiaLanguageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn prodia_language_model_value(
  model_id : String,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> ProdiaLanguageModel {
  {
    provider_name: "prodia",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
/// Unsupported-setting warnings plus the prompt text and optional input
/// image extracted from the prompt.
async fn ProdiaLanguageModel::prepare(
  self : ProdiaLanguageModel,
  options : @provider.LanguageModelV4CallOptions,
) -> (String, (Bytes, String)?, Array[@provider.Warning]) {
  let warnings : Array[@provider.Warning] = []
  if options.temperature is Some(_) {
    warnings.push(@provider.Warning::unsupported("temperature"))
  }
  if options.top_p is Some(_) {
    warnings.push(@provider.Warning::unsupported("topP"))
  }
  if options.top_k is Some(_) {
    warnings.push(@provider.Warning::unsupported("topK"))
  }
  if options.seed is Some(_) {
    warnings.push(@provider.Warning::unsupported("seed"))
  }
  if options.max_output_tokens is Some(_) {
    warnings.push(@provider.Warning::unsupported("maxOutputTokens"))
  }
  if options.stop_sequences.length() > 0 {
    warnings.push(@provider.Warning::unsupported("stopSequences"))
  }
  if options.presence_penalty is Some(_) {
    warnings.push(@provider.Warning::unsupported("presencePenalty"))
  }
  if options.frequency_penalty is Some(_) {
    warnings.push(@provider.Warning::unsupported("frequencyPenalty"))
  }
  if options.tools.length() > 0 {
    warnings.push(@provider.Warning::unsupported("tools"))
  }
  if options.tool_choice is Some(_) {
    warnings.push(@provider.Warning::unsupported("toolChoice"))
  }
  match options.response_format {
    @provider.V4ResponseText => ()
    _ => warnings.push(@provider.Warning::unsupported("responseFormat"))
  }
  match options.reasoning {
    @provider.V4ReasoningProviderDefault => ()
    _ =>
      warnings.push(
        @provider.Warning::Unsupported(
          feature="reasoning",
          details="This provider does not support reasoning configuration.",
        ),
      )
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  // Collect the last user message's text parts and image file part.
  let mut prompt = ""
  let mut image : (Bytes, String)? = None
  for message in options.prompt.messages {
    match message {
      @provider.V4UserMessage(content~, ..) => {
        let texts : Array[String] = []
        for part in content {
          match part {
            @provider.V4PromptText(text~, ..) => texts.push(text)
            @provider.V4PromptFile(data~, media_type~, ..) => {
              let resolved = match data {
                @provider.V4FileData(payload) =>
                  (@base64.decode(payload), media_type)
                @provider.V4FileBytes(bytes) => (bytes, media_type)
                @provider.V4FileUrl(url) => {
                  let downloaded = @provider_utils.download_file(
                    provider_name=self.provider_name,
                    url~,
                    timeout_ms=self.idle_timeout_ms,
                    retry_policy=options.retry_policy,
                    cancellation_token?=options.cancellation_token,
                    trusted_origin=self.base_url,
                    transport=self.http_transport,
                  )
                  (downloaded.data, downloaded.media_type)
                }
                _ =>
                  raise @provider.UnsupportedFunctionalityError(
                    functionality="file parts with provider references",
                  )
              }
              image = Some(resolved)
            }
            _ => ()
          }
        }
        for text in texts {
          prompt = if prompt == "" { text } else { "\{prompt}\n\{text}" }
        }
      }
      _ => ()
    }
  }
  if resolution.values.get("aspect_ratio") is Some(value) {
    ignore(value)
  }
  (prompt, image, warnings)
}

///|
fn prodia_language_job_body(
  model_id~ : String,
  prompt~ : String,
  aspect_ratio~ : Json?,
) -> Json {
  let config : Map[String, Json] = Map([
    ("prompt", Json::string(prompt)),
    ("include_messages", Json::boolean(true)),
  ])
  if aspect_ratio is Some(value) {
    config["aspect_ratio"] = value
  }
  let outer : Map[String, Json] = Map([
    ("type", Json::string(model_id)),
    ("config", Json::object(config)),
  ])
  Json::object(outer)
}

///|
pub impl @provider.LanguageModelV4 for ProdiaLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for ProdiaLanguageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.LanguageModelV4 for ProdiaLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.LanguageModelV4 for ProdiaLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
pub impl @provider.LanguageModelV4 for ProdiaLanguageModel with fn do_generate(
  self,
  options,
) {
  let (prompt, image, warnings) = self.prepare(options)
  let aspect_ratio : Json? = None
  let job_json = prodia_language_job_body(
    model_id=self.model_id,
    prompt~,
    aspect_ratio~,
  ).stringify()
  let fields : Array[@provider_utils.MultipartField] = [
    @provider_utils.MultipartField::text(name="job", value=job_json),
  ]
  if image is Some((bytes, media_type)) {
    fields.push(
      @provider_utils.MultipartField::file(
        name="input",
        filename="input",
        media_type~,
        data=bytes,
      ),
    )
  }
  let form_data = @provider_utils.encode_multipart_form_data(fields)
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_multipart_binary(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/job?price=true"),
    headers=prodia_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
      content_type=form_data.content_type,
      accept="multipart/form-data",
    ),
    form_data~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=prodia_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let parts = @provider_utils.parse_multipart_response(
    content_type=response.response.headers.get("content-type").unwrap_or(""),
    data=response.value,
  )
  let job = decode_prodia_job_part(parts)
  // The assistant text rides on the `output` part with a .txt filename;
  // generated images arrive as image/* parts.
  let mut text : String? = None
  let files : Array[@provider.LanguageModelV4File] = []
  for part in parts {
    let disposition = part.headers.get("content-disposition").unwrap_or("")
    let media_type = part.headers.get("content-type").unwrap_or("")
    if disposition.contains("name=\"output\"") && disposition.contains(".txt") {
      text = Some(@utf8.decode(part.body))
    } else if media_type.has_prefix("image/") {
      files.push({
        media_type,
        data: @provider.V4GeneratedFileBase64(
          @base64.encode(part.body, padding=true),
        ),
        provider_metadata: Map([]),
      })
    }
  }
  let content : Array[@provider.LanguageModelV4Content] = []
  match text {
    Some(value) =>
      content.push(
        @provider.V4TextOutput({ text: value, provider_metadata: Map([]), }),
      )
    None => ()
  }
  for file in files {
    content.push(@provider.V4FileOutput(file))
  }
  {
    content,
    finish_reason: { unified: @provider.V4FinishStop, raw: None, },
    usage: @provider.LanguageModelV4Usage::unknown(),
    provider_metadata: prodia_job_metadata(job),
    request: Some(
      @provider.RequestMetadata::new(
        url=self.base_url,
        headers=@provider_utils.copy_headers(options.headers),
        body=job_json,
      ),
    ),
    response: Some({
      ..@provider.ResponseMetadata::empty(),
      model_id: Some(self.model_id),
      headers: response.response.headers,
    }),
    warnings,
  }
}

///|
pub impl @provider.LanguageModelV4 for ProdiaLanguageModel with fn do_stream(
  self,
  options,
  on_event,
) {
  // Prodia has no streaming endpoint; the collected result is replayed as
  // a chunk stream (matching upstream doStream behavior).
  let result = (self as &@provider.LanguageModelV4).do_generate(options)
  on_event(
    @provider.V4StreamStart(warnings=@provider.copy_warnings(result.warnings)),
  )
  match result.response {
    Some(metadata) => on_event(@provider.V4ResponseMetadataReady(metadata))
    None => ()
  }
  for entry in result.content {
    match entry {
      @provider.V4TextOutput(value) => {
        on_event(@provider.V4TextStart(id="text-0", provider_metadata=Map([])))
        on_event(
          @provider.V4TextDelta(
            id="text-0",
            delta=value.text,
            provider_metadata=Map([]),
          ),
        )
        on_event(@provider.V4TextEnd(id="text-0", provider_metadata=Map([])))
      }
      @provider.V4FileOutput(file) => on_event(@provider.V4FileReady(file))
      _ => ()
    }
  }
  on_event(
    @provider.V4Finish(
      usage=result.usage,
      reason=result.finish_reason,
      provider_metadata=result.provider_metadata,
    ),
  )
  @provider.LanguageModelV4StreamResult::new(None, None)
}
