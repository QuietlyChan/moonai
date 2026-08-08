///|
/// One URL considered during high-level prompt conversion.
pub(all) struct DownloadRequest {
  url : String
  is_url_supported_by_model : Bool
} derive(Debug, Eq)

///|
/// Construct a request passed to a custom prompt asset downloader.
pub fn DownloadRequest::new(
  url~ : String,
  is_url_supported_by_model~ : Bool,
) -> DownloadRequest {
  { url, is_url_supported_by_model }
}

///|
/// Binary data returned for one downloaded prompt asset.
pub(all) struct DownloadedAsset {
  data : Bytes
  media_type : String?
} derive(Debug, Eq)

///|
/// Construct a downloaded prompt asset.
pub fn DownloadedAsset::new(
  data~ : Bytes,
  media_type? : String,
) -> DownloadedAsset {
  { data, media_type }
}

///|
/// Custom prompt-asset downloader. Results correspond to requests by index;
/// `None` means that the original URL should be passed to the model.
pub type DownloadFunction = async (Array[DownloadRequest]) -> Array[
  DownloadedAsset?,
]

///|
/// Provider capabilities required by prompt asset normalization.
///
/// Keeping this small context independent from a concrete model trait lets
/// the same downloader serve both the ChatModel wire surface and the V4
/// language-model surface.
pub(all) struct PromptModelContext {
  provider_name : String
  supported_urls : Array[@provider.SupportedUrlRule]
}

///|
/// Construct prompt capabilities for one provider model.
pub fn PromptModelContext::new(
  provider_name~ : String,
  supported_urls~ : Array[@provider.SupportedUrlRule],
) -> PromptModelContext {
  { provider_name, supported_urls: supported_urls.copy() }
}

///|
/// Capture the prompt capabilities exposed by a wire-level ChatModel.
pub fn PromptModelContext::from_chat_model(
  model : &@provider.ChatModel,
) -> PromptModelContext {
  PromptModelContext::new(
    provider_name=model.provider(),
    supported_urls=model.supported_urls(),
  )
}

///|
/// Capture the prompt capabilities exposed by a V4 language model.
pub fn PromptModelContext::from_language_model_v4(
  model : &@provider.LanguageModelV4,
) -> PromptModelContext {
  PromptModelContext::new(
    provider_name=model.provider(),
    supported_urls=model.supported_urls(),
  )
}

///|
priv struct PlannedDownload {
  url : String
  media_type : String
}

///|
fn planned_downloads(
  messages : Array[@provider_utils.ModelMessage],
) -> Array[PlannedDownload] {
  let planned : Array[PlannedDownload] = []
  let plan_tool_result = fn(
    output : @provider_utils.ModelToolResultOutput,
  ) -> Unit {
    match output {
      @provider_utils.ModelToolContent(value~, ..) =>
        for part in value {
          match part {
            @provider_utils.ModelToolResultFileUrl(url~, media_type~, ..) =>
              planned.push({ url, media_type })
            _ => ()
          }
        }
      _ => ()
    }
  }
  for message in messages {
    for part in message.parts {
      match part.without_provider_options() {
        @provider_utils.ModelImageUrl(url) =>
          planned.push({ url, media_type: "image" })
        @provider_utils.ModelFileUrl(url~, media_type~, ..) =>
          planned.push({ url, media_type })
        @provider_utils.ModelReasoningFileUrl(url~, media_type~) =>
          planned.push({ url, media_type })
        @provider_utils.ModelToolResultPart(result~) =>
          plan_tool_result(result.output)
        _ => ()
      }
    }
  }
  planned
}

///|
async fn default_download_assets(
  requests : Array[DownloadRequest],
  provider_name : String,
  retry_policy : @provider.RetryPolicy,
  cancellation_token : @provider.CancellationToken?,
) -> Array[DownloadedAsset?] {
  let tasks : Array[async () -> DownloadedAsset?] = []
  for request in requests {
    let current = request
    tasks.push(() => {
      if current.is_url_supported_by_model {
        return None
      }
      let downloaded = @provider_utils.download_file(
        provider_name~,
        url=current.url,
        retry_policy~,
        cancellation_token?,
      )
      Some(
        DownloadedAsset::new(
          data=downloaded.data,
          media_type=downloaded.media_type,
        ),
      )
    })
  }
  @async.all(tasks)
}

///|
fn resolved_download_media_type(
  planned : PlannedDownload,
  asset : DownloadedAsset,
  encoded_data : String,
) -> String raise {
  match
    @provider_utils.detect_media_type(encoded_data, top_level_type="image") {
    Some(value) => return value
    None => ()
  }
  let media_type = match asset.media_type {
    Some(value) if !@provider_utils.is_full_media_type(planned.media_type) ||
      planned.media_type == "application/octet-stream" => value
    _ => planned.media_type
  }
  if @provider_utils.is_full_media_type(media_type) {
    media_type
  } else {
    @provider_utils.resolve_full_media_type(media_type, encoded_data)
  }
}

///|
fn restore_model_part_options(
  part : @provider_utils.ModelContentPart,
  options : Map[String, Json],
) -> @provider_utils.ModelContentPart {
  if options.length() == 0 {
    part
  } else {
    part.with_provider_options(options)
  }
}

///|
/// Rewrite a URL-backed high-level content part after the shared downloader
/// has materialized it. Provider options stay attached to the replacement.
fn rewrite_downloaded_model_part(
  part : @provider_utils.ModelContentPart,
  downloaded_assets : Map[String, DownloadedAsset],
) -> @provider_utils.ModelContentPart raise {
  let part_options = part.provider_options()
  let replacement : @provider_utils.ModelContentPart? = match
    part.without_provider_options() {
    @provider_utils.ModelImageUrl(url) =>
      match downloaded_assets.get(url) {
        Some(asset) => {
          let data = @base64.encode(asset.data)
          let media_type = resolved_download_media_type(
            { url, media_type: "image" },
            asset,
            data,
          )
          Some(@provider_utils.ModelContentPart::image_data(data~, media_type~))
        }
        None => None
      }
    @provider_utils.ModelFileUrl(url~, media_type~, filename~) =>
      match downloaded_assets.get(url) {
        Some(asset) => {
          let data = @base64.encode(asset.data)
          let resolved_media_type = resolved_download_media_type(
            { url, media_type },
            asset,
            data,
          )
          Some(
            @provider_utils.ModelContentPart::file_data(
              data~,
              media_type=resolved_media_type,
              filename~,
            ),
          )
        }
        None => None
      }
    @provider_utils.ModelReasoningFileUrl(url~, media_type~) =>
      match downloaded_assets.get(url) {
        Some(asset) => {
          let data = @base64.encode(asset.data)
          let resolved_media_type = resolved_download_media_type(
            { url, media_type },
            asset,
            data,
          )
          Some(
            @provider_utils.ModelContentPart::reasoning_file_data(
              data~,
              media_type=resolved_media_type,
            ),
          )
        }
        None => None
      }
    _ => None
  }
  match replacement {
    Some(value) => restore_model_part_options(value, part_options)
    None => part
  }
}

///|
/// Rewrite URL-backed files nested inside a structured tool result.
fn rewrite_tool_result_content_part(
  part : @provider_utils.ModelToolResultContentPart,
  downloaded_assets : Map[String, DownloadedAsset],
) -> @provider_utils.ModelToolResultContentPart raise {
  match part {
    @provider_utils.ModelToolResultFileUrl(
      url~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      match downloaded_assets.get(url) {
        Some(asset) => {
          let data = @base64.encode(asset.data)
          let resolved_media_type = resolved_download_media_type(
            { url, media_type },
            asset,
            data,
          )
          @provider_utils.ModelToolResultFileData(
            data~,
            media_type=resolved_media_type,
            filename~,
            provider_options~,
          )
        }
        None => part
      }
    _ => part
  }
}

///|
/// Rewrite all downloadable URLs in one structured tool result.
fn rewrite_tool_result(
  result : @provider_utils.ModelToolResult,
  downloaded_assets : Map[String, DownloadedAsset],
) -> @provider_utils.ModelToolResult raise {
  let output = match result.output {
    @provider_utils.ModelToolContent(value~, provider_options~) =>
      @provider_utils.ModelToolContent(
        value=[
          for part in value => {
            rewrite_tool_result_content_part(part, downloaded_assets)
          }
        ],
        provider_options~,
      )
    other => other
  }
  {
    tool_call_id: result.tool_call_id,
    tool_name: result.tool_name,
    output,
    provider_options: result.provider_options,
  }
}

///|
fn rewrite_downloaded_parts(
  messages : Array[@provider_utils.ModelMessage],
  downloaded_assets : Map[String, DownloadedAsset],
) -> Array[@provider_utils.ModelMessage] raise {
  let rewritten : Array[@provider_utils.ModelMessage] = []
  for message in messages {
    let parts : Array[@provider_utils.ModelContentPart] = []
    for part in message.parts {
      match part.without_provider_options() {
        @provider_utils.ModelToolResultPart(result~) =>
          parts.push(
            @provider_utils.ModelContentPart::tool_result(
              rewrite_tool_result(result, downloaded_assets),
            ),
          )
        _ => parts.push(rewrite_downloaded_model_part(part, downloaded_assets))
      }
    }
    rewritten.push(message.with_parts(parts))
  }
  rewritten
}

///|
/// Download URL-backed prompt assets that a model cannot consume natively.
pub async fn download_prompt_assets_with_context(
  messages : Array[@provider_utils.ModelMessage],
  context : PromptModelContext,
  download : DownloadFunction?,
  retry_policy : @provider.RetryPolicy,
  cancellation_token : @provider.CancellationToken?,
) -> Array[@provider_utils.ModelMessage] {
  let supported_urls = context.supported_urls
  let planned = planned_downloads(messages)
  let requests = [
    for item in planned => {
      DownloadRequest::new(
        url=item.url,
        is_url_supported_by_model=@provider_utils.is_url_supported(
          media_type=item.media_type,
          url=item.url,
          supported_urls~,
        ),
      )
    }
  ]
  let results = match download {
    Some(custom_download) => custom_download(requests)
    None =>
      default_download_assets(
        requests,
        context.provider_name,
        retry_policy,
        cancellation_token,
      )
  }
  guard results.length() == planned.length() else {
    fail(
      "download function returned \{results.length()} results for \{planned.length()} requests",
    )
  }
  let downloaded_assets : Map[String, DownloadedAsset] = Map([])
  for index, result in results {
    match result {
      Some(asset) => downloaded_assets[planned[index].url] = asset
      None => ()
    }
  }
  rewrite_downloaded_parts(messages, downloaded_assets)
}

///|
/// Download prompt assets for a wire-level ChatModel.
pub async fn download_prompt_assets(
  messages : Array[@provider_utils.ModelMessage],
  model : &@provider.ChatModel,
  download : DownloadFunction?,
  retry_policy : @provider.RetryPolicy,
  cancellation_token : @provider.CancellationToken?,
) -> Array[@provider_utils.ModelMessage] {
  download_prompt_assets_with_context(
    messages,
    PromptModelContext::from_chat_model(model),
    download,
    retry_policy,
    cancellation_token,
  )
}

///|
fn convert_model_content_part(
  part : @provider_utils.ModelContentPart,
) -> @provider.LanguageModelContentPart {
  let options = part.provider_options()
  let converted = match part.without_provider_options() {
    @provider_utils.ModelText(value) =>
      @provider.LanguageModelContentPart::text(value)
    @provider_utils.ModelImageUrl(value) =>
      @provider.LanguageModelContentPart::image_url(value)
    @provider_utils.ModelImageData(data~, media_type~) =>
      @provider.LanguageModelContentPart::image_data(data~, media_type~)
    @provider_utils.ModelAudioData(data~, format~) =>
      @provider.LanguageModelContentPart::audio_data(data~, format~)
    @provider_utils.ModelFileUrl(url~, media_type~, filename~) =>
      @provider.LanguageModelContentPart::file_url(url~, media_type~, filename~)
    @provider_utils.ModelFileData(data~, media_type~, filename~) =>
      @provider.LanguageModelContentPart::file_data(
        data~,
        media_type~,
        filename~,
      )
    @provider_utils.ModelFileReference(reference~, media_type~, filename~) =>
      @provider.LanguageModelContentPart::file_reference(
        reference~,
        media_type~,
        filename~,
      )
    @provider_utils.ModelReasoning(value) =>
      @provider.LanguageModelContentPart::reasoning(value)
    @provider_utils.ModelReasoningFileUrl(url~, media_type~) =>
      @provider.LanguageModelContentPart::reasoning_file_url(url~, media_type~)
    @provider_utils.ModelReasoningFileData(data~, media_type~) =>
      @provider.LanguageModelContentPart::reasoning_file_data(
        data~,
        media_type~,
      )
    @provider_utils.ModelCustom(kind~) =>
      @provider.LanguageModelContentPart::custom(kind)
    @provider_utils.ModelToolCallPart(call~) =>
      @provider.LanguageModelContentPart::tool_call(
        convert_model_tool_call(call),
      )
    @provider_utils.ModelToolResultPart(result~) =>
      @provider.LanguageModelContentPart::tool_result(
        convert_model_tool_result(result),
      )
    @provider_utils.ModelToolApprovalRequestPart(request~) =>
      @provider.LanguageModelContentPart::tool_approval_request(
        convert_model_tool_approval_request(request),
      )
    @provider_utils.ModelToolApprovalResponsePart(response~) =>
      @provider.LanguageModelContentPart::tool_approval_response(
        convert_model_tool_approval_response(response),
      )
    @provider_utils.ModelPartProviderOptions(..) => abort("unreachable")
  }
  if options.length() == 0 {
    converted
  } else {
    converted.with_provider_options(options)
  }
}

///|
fn convert_model_tool_call(
  call : @provider_utils.ModelToolCall,
) -> @provider.ToolCall {
  @provider.ToolCall::new(
    id=call.id,
    name=call.name,
    arguments=call.input.stringify(),
    provider_executed=call.provider_executed,
    dynamic=call.dynamic,
    provider_metadata=call.provider_options,
  )
}

///|
fn convert_model_tool_result_content_part(
  part : @provider_utils.ModelToolResultContentPart,
) -> @provider.LanguageModelToolResultContentPart {
  match part {
    @provider_utils.ModelToolResultText(text~, provider_options~) =>
      @provider.LanguageModelToolText(text~, provider_options~)
    @provider_utils.ModelToolResultFileUrl(
      url~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      @provider.LanguageModelToolFileUrl(
        url~,
        media_type~,
        filename~,
        provider_options~,
      )
    @provider_utils.ModelToolResultFileData(
      data~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      @provider.LanguageModelToolFileData(
        data~,
        media_type~,
        filename~,
        provider_options~,
      )
    @provider_utils.ModelToolResultFileReference(
      reference~,
      media_type~,
      filename~,
      provider_options~
    ) =>
      @provider.LanguageModelToolFileReference(
        reference~,
        media_type~,
        filename~,
        provider_options~,
      )
    @provider_utils.ModelToolResultCustom(provider_options~) =>
      @provider.LanguageModelToolCustom(provider_options~)
  }
}

///|
fn convert_model_tool_result_output(
  output : @provider_utils.ModelToolResultOutput,
) -> @provider.LanguageModelToolResultOutput {
  match output {
    @provider_utils.ModelToolText(value~, provider_options~) =>
      @provider.LanguageModelToolTextOutput(value~, provider_options~)
    @provider_utils.ModelToolJson(value~, provider_options~) =>
      @provider.LanguageModelToolJsonOutput(value~, provider_options~)
    @provider_utils.ModelToolExecutionDenied(reason~, provider_options~) =>
      @provider.LanguageModelToolExecutionDenied(reason~, provider_options~)
    @provider_utils.ModelToolErrorText(value~, provider_options~) =>
      @provider.LanguageModelToolErrorText(value~, provider_options~)
    @provider_utils.ModelToolErrorJson(value~, provider_options~) =>
      @provider.LanguageModelToolErrorJson(value~, provider_options~)
    @provider_utils.ModelToolContent(value~, provider_options~) =>
      @provider.LanguageModelToolContent(
        value=[
          for part in value => convert_model_tool_result_content_part(part)
        ],
        provider_options~,
      )
  }
}

///|
fn convert_model_tool_result(
  result : @provider_utils.ModelToolResult,
) -> @provider.LanguageModelToolResult {
  {
    tool_call_id: result.tool_call_id,
    tool_name: result.tool_name,
    output: convert_model_tool_result_output(result.output),
    provider_options: result.provider_options,
  }
}

///|
fn convert_model_tool_approval_request(
  request : @provider_utils.ModelToolApprovalRequest,
) -> @provider.LanguageModelToolApprovalRequest {
  {
    approval_id: request.approval_id,
    tool_call_id: request.tool_call_id,
    is_automatic: request.is_automatic,
    signature: request.signature,
  }
}

///|
fn convert_model_tool_approval_response(
  response : @provider_utils.ModelToolApprovalResponse,
) -> @provider.LanguageModelToolApprovalResponse {
  {
    approval_id: response.approval_id,
    approved: response.approved,
    reason: response.reason,
    provider_executed: response.provider_executed,
    provider_options: response.provider_options,
  }
}

///|
fn convert_model_message(
  message : @provider_utils.ModelMessage,
) -> @provider.LanguageModelMessage {
  let role = match message.role {
    @provider_utils.ModelSystem => @provider.System
    @provider_utils.ModelUser => @provider.User
    @provider_utils.ModelAssistant => @provider.Assistant
    @provider_utils.ModelTool(tool_call_id) => @provider.Tool(tool_call_id)
  }
  @provider.LanguageModelMessage::new(
    role,
    content=message.content,
    parts=[ for part in message.parts => convert_model_content_part(part) ],
    tool_calls=[
      for call in message.tool_calls => convert_model_tool_call(call)
    ],
    reasoning_content?=message.reasoning_content,
    provider_options=message.provider_options,
  )
}

///|
/// Convert a standardized user-facing prompt into the provider contract.
pub async fn convert_to_language_model_prompt_with_context(
  prompt : StandardizedPrompt,
  context : PromptModelContext,
  download : DownloadFunction?,
  retry_policy : @provider.RetryPolicy,
  cancellation_token : @provider.CancellationToken?,
) -> @provider.LanguageModelPrompt {
  let messages : Array[@provider_utils.ModelMessage] = []
  match prompt.instructions {
    Some(instructions) =>
      for message in instructions.as_messages() {
        messages.push(message)
      }
    None => ()
  }
  for message in prompt.messages {
    messages.push(message.copy())
  }
  let normalized = download_prompt_assets_with_context(
    messages, context, download, retry_policy, cancellation_token,
  )
  let normalized = normalize_model_messages(normalized)
  [
    for message in normalized => convert_model_message(message)
  ]
}

///|
/// Convert a standardized prompt for a wire-level ChatModel.
pub async fn convert_to_language_model_prompt(
  prompt : StandardizedPrompt,
  model : &@provider.ChatModel,
  download : DownloadFunction?,
  retry_policy : @provider.RetryPolicy,
  cancellation_token : @provider.CancellationToken?,
) -> @provider.LanguageModelPrompt {
  convert_to_language_model_prompt_with_context(
    prompt,
    PromptModelContext::from_chat_model(model),
    download,
    retry_policy,
    cancellation_token,
  )
}
