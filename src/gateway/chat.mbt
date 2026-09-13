///|
/// The AI Gateway language model: the V4-native /language-model protocol.
/// The gateway accepts the full V4 call options as the request body and
/// answers with V4 result (or stream part) JSON.
struct GatewayLanguageModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn gateway_chat_value(
  model_id : GatewayModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> GatewayLanguageModel {
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
fn GatewayLanguageModel::request_headers(
  self : GatewayLanguageModel,
  extra~ : Map[String, String],
  streaming~ : Bool,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  gateway_request_headers(
    api_key=self.api_key,
    headers=self.headers,
    extra~,
    model_id=self.model_id,
    streaming~,
  )
}

///|
fn GatewayLanguageModel::gateway_language_model_url(
  self : GatewayLanguageModel,
) -> String {
  @provider_utils.append_path(self.base_url, "/language-model")
}

///|
/// Decode a V4 content part from the gateway generate response.
fn gateway_decode_content(
  part : Json,
  generate_id : @provider_utils.IdGenerator,
) -> @provider.LanguageModelV4Content? {
  match part {
    { "type": "text", "text": String(text), .. } if text != "" =>
      Some(@provider.V4TextOutput({ text, provider_metadata: Map([]), }))
    { "type": "reasoning", "text": String(text), .. } if text != "" =>
      Some(@provider.V4ReasoningOutput({ text, provider_metadata: Map([]), }))
    { "type": "tool-call", .. } => {
      let tool_call_id = match part {
        { "toolCallId": String(id), .. } => id
        _ => generate_id()
      }
      let tool_name = match part {
        { "toolName": String(name), .. } => name
        _ => ""
      }
      let input_value = match part {
        Object(fields) => fields.get("input")
        _ => None
      }
      let input = match input_value {
        Some(Object(fields)) => Json::object(fields)
        _ => Json::object(Map([]))
      }
      Some(
        @provider.V4ToolCallOutput({
          tool_call_id,
          tool_name,
          input: input.stringify(),
          provider_executed: part is { "providerExecuted": True, .. },
          dynamic: false,
          provider_metadata: Map([]),
        }),
      )
    }
    { "type": "source", "sourceType": "url", "url": String(url), .. } =>
      Some(
        @provider.V4SourceOutput(
          @provider.V4UrlSource(
            id=generate_id(),
            url~,
            title=None,
            provider_metadata=Map([]),
          ),
        ),
      )
    {
      "type": "file",
      "data": { "type": "base64", "data": String(payload), .. },
      "mediaType": String(media_type),
      ..
    } =>
      Some(
        @provider.V4FileOutput({
          media_type,
          data: @provider.V4GeneratedFileBase64(payload),
          provider_metadata: Map([]),
        }),
      )
    {
      "type": "file",
      "data": { "type": "url", "url": String(url), .. },
      "mediaType": String(media_type),
      ..
    } =>
      Some(
        @provider.V4FileOutput({
          media_type,
          data: @provider.V4GeneratedFileUrl(url),
          provider_metadata: Map([]),
        }),
      )
    _ => None
  }
}

///|
/// Decode the gateway generate response into the V4 result.
fn gateway_decode_generate_response(
  value : Json,
) -> @provider.LanguageModelV4GenerateResult raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  let generate_id : @provider_utils.IdGenerator = @provider_utils.generate_id
  let content : Array[@provider.LanguageModelV4Content] = []
  if value is Object(fields) {
    if fields.get("content") is Some(Array(parts)) {
      for part in parts {
        match gateway_decode_content(part, generate_id) {
          Some(entry) => content.push(entry)
          None => ()
        }
      }
    }
  }
  {
    content,
    finish_reason: gateway_finish_reason(
      match value {
        Object(fields) => fields.get("finishReason")
        _ => None
      },
    ),
    usage: gateway_usage(
      match value {
        Object(fields) => fields.get("usage")
        _ => None
      },
    ),
    provider_metadata: Map([]),
    request: None,
    response: None,
    warnings: gateway_decode_warnings(
      match value {
        Object(fields) => fields.get("warnings")
        _ => None
      },
    ),
  }
}

///|
/// Forward server-returned warnings (upstream #20675) instead of
/// replacing them with a locally constructed empty array.
fn gateway_decode_warnings(value : Json?) -> Array[@provider.Warning] {
  let warnings : Array[@provider.Warning] = []
  match value {
    Some(Array(items)) =>
      for item in items {
        match item {
          { "type": String(kind), .. } => {
            let details = match item {
              { "details": String(details), .. } => details
              _ => ""
            }
            if kind == "unsupported" || kind == "compatibility" {
              let feature = match item {
                { "feature": String(feature), .. } => feature
                _ => kind
              }
              warnings.push(@provider.Warning::Unsupported(feature~, details~))
            } else {
              warnings.push(@provider.Warning::Other(message=kind))
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  warnings
}

///|
pub impl @provider.LanguageModelV4 for GatewayLanguageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for GatewayLanguageModel with fn provider(
  self,
) -> String {
  self.provider_name
}

///|
pub impl @provider.LanguageModelV4 for GatewayLanguageModel with fn model_id(
  self,
) -> String {
  self.model_id
}

///|
pub impl @provider.LanguageModelV4 for GatewayLanguageModel with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  [@provider.SupportedUrlRule::all("*/*")]
}

///|
pub impl @provider.LanguageModelV4 for GatewayLanguageModel with fn do_generate(
  self,
  options,
) {
  let body = gateway_encode_options(options)
  let cancellation_token = options.cancellation_token
  let response = @provider_utils.post_json(
    provider_name=self.provider_name,
    url=self.gateway_language_model_url(),
    headers=self.request_headers(extra=options.headers, streaming=false),
    body~,
    timeout_ms=self.idle_timeout_ms,
    retry_policy=options.retry_policy,
    cancellation_token?,
    error_to_message=gateway_error_to_message,
    is_retryable_response=(_status_code, _error) => None,
    transport=self.http_transport,
  )
  let result = @provider_utils.handle_json_response(response, value => {
    gateway_decode_generate_response(value)
  })
  {
    ..result,
    request: Some(
      @provider.RequestMetadata::new(
        url=self.base_url,
        headers=@provider_utils.copy_headers(options.headers),
        body=body.stringify(),
      ),
    ),
    response: Some({
      ..result.response.unwrap_or(@provider.ResponseMetadata::empty()),
      headers: response.response.headers,
      body: Some(response.value.stringify()),
    }),
  }
}
