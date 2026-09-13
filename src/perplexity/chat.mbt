///|
/// Perplexity chat completions with search grounding: the OpenAI-shaped wire
/// plus citations/images blocks and search-specific usage fields.
struct PerplexityLanguageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  id_generator : @provider_utils.IdGenerator
  http_transport : &@provider_utils.HttpTransport
}

///|
fn perplexity_chat_value(
  model_id : PerplexityLanguageModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
  id_generator~ : @provider_utils.IdGenerator,
) -> PerplexityLanguageModel {
  {
    provider_name: "perplexity",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    id_generator,
    http_transport,
  }
}

///|
/// Unsupported-setting warnings plus the request body for a call.
fn PerplexityLanguageModel::perplexity_prepare(
  self : PerplexityLanguageModel,
  options : @provider.LanguageModelV4CallOptions,
) -> (Json, Array[@provider.Warning]) raise {
  let warnings : Array[@provider.Warning] = []
  if options.top_k is Some(_) {
    warnings.push(@provider.Warning::unsupported("topK"))
  }
  if options.stop_sequences.length() > 0 {
    warnings.push(@provider.Warning::unsupported("stopSequences"))
  }
  if options.seed is Some(_) {
    warnings.push(@provider.Warning::unsupported("seed"))
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
  let conversion = @openai_compatible.default_openai_compatible_v4_prompt_converter(
    options.prompt,
    self.provider_name,
  )
  for warning in conversion.warnings {
    warnings.push(warning)
  }
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let fields : Map[String, Json] = Map([
    ("model", Json::string(self.model_id)),
    ("messages", Json::array(conversion.messages)),
  ])
  if options.max_output_tokens is Some(value) {
    fields["max_tokens"] = Json::number(value.to_double())
  }
  if options.temperature is Some(value) {
    fields["temperature"] = Json::number(value)
  }
  if options.top_p is Some(value) {
    fields["top_p"] = Json::number(value)
  }
  if options.top_k is Some(value) {
    fields["top_k"] = Json::number(value)
  }
  if options.frequency_penalty is Some(value) {
    fields["frequency_penalty"] = Json::number(value)
  }
  if options.presence_penalty is Some(value) {
    fields["presence_penalty"] = Json::number(value)
  }
  match options.response_format {
    @provider.V4ResponseJson(format) =>
      fields["response_format"] = {
        "type": "json_schema",
        "json_schema": { "schema": format.schema },
      }
    _ => ()
  }
  for entry in resolution.values.iter2() {
    fields[entry.0] = entry.1
  }
  (Json::object(fields), warnings)
}

///|
pub impl @provider.LanguageModelV4 for PerplexityLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for PerplexityLanguageModel with fn provider(
  _self,
) -> String {
  "perplexity"
}

///|
pub impl @provider.LanguageModelV4 for PerplexityLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.LanguageModelV4 for PerplexityLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
pub impl @provider.LanguageModelV4 for PerplexityLanguageModel with fn do_generate(
  self,
  options,
) {
  let (body, warnings) = self.perplexity_prepare(options)
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=@provider_utils.append_path(self.base_url, "/chat/completions"),
    headers=perplexity_request_headers(
      api_key=self.api_key,
      headers=self.headers,
      extra=options.headers,
    ),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=perplexity_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let value = response.value
  let content : Array[@provider.LanguageModelV4Content] = []
  let mut text = ""
  if value is Object(fields) {
    if fields.get("choices") is Some(Array(choices)) && choices.length() > 0 {
      match choices[0] {
        { "message": { "content": String(value), .. }, .. } => text = value
        _ => ()
      }
    }
  }
  if text != "" {
    content.push(@provider.V4TextOutput({ text, provider_metadata: Map([]), }))
  }
  for url in perplexity_citations(value) {
    content.push(
      @provider.V4SourceOutput(
        @provider.V4UrlSource(
          id=(self.id_generator)(),
          url~,
          title=None,
          provider_metadata=Map([]),
        ),
      ),
    )
  }
  let mut finish_raw : String? = None
  if value is Object(fields) {
    if fields.get("choices") is Some(Array(choices)) && choices.length() > 0 {
      match choices[0] {
        { "finish_reason": String(reason), .. } => finish_raw = Some(reason)
        _ => ()
      }
    }
  }
  {
    content,
    finish_reason: perplexity_map_finish_reason(finish_raw),
    usage: @provider.LanguageModelV4Usage::from_token_usage_json(
      match value {
        Object(fields) => fields.get("usage")
        _ => None
      },
    ),
    provider_metadata: perplexity_provider_metadata(value),
    request: Some(
      @provider.RequestMetadata::new(
        url=self.base_url,
        headers=@provider_utils.copy_headers(options.headers),
        body=body.stringify(),
      ),
    ),
    response: Some({
      ..perplexity_response_metadata(value),
      headers: response.response.headers,
      body: Some(value.stringify()),
    }),
    warnings,
  }
}
