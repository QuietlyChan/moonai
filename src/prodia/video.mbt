///|
/// The Prodia video model: POST /job?price=true (JSON, or multipart with an
/// input image) returns a multipart response with the job result and the
/// video bytes.
struct ProdiaVideoModel {
  provider_name : String
  api_key : String
  base_url : String
  model_id : String
  headers : Map[String, String]
  idle_timeout_ms : Int
  http_transport : &@provider_utils.HttpTransport
}

///|
fn prodia_video_value(
  model_id : ProdiaVideoModelId,
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> ProdiaVideoModel {
  {
    provider_name: "prodia.video",
    api_key,
    base_url,
    model_id,
    headers,
    idle_timeout_ms,
    http_transport,
  }
}

///|
/// Extract the video part: named `output`, or any `video/*` part.
fn decode_prodia_video_part(
  parts : Array[@provider_utils.MultipartResponsePart],
) -> (Bytes, String) raise {
  let video = @provider_utils.multipart_response_part_by_name(
    parts,
    name="output",
  )
  let video = match video {
    Some(part) => Some(part)
    None =>
      @provider_utils.multipart_response_part_by_content_type_prefix(
        parts,
        prefix="video/",
      )
  }
  guard video is Some(part) else {
    fail("prodia multipart response missing output video")
  }
  let media_type = part.headers.get("content-type").unwrap_or("video/mp4")
  (part.body, media_type)
}

///|
pub impl @provider.VideoModelV4 for ProdiaVideoModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.VideoModelV4 for ProdiaVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.VideoModelV4 for ProdiaVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.VideoModelV4 for ProdiaVideoModel with fn max_videos_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
/// Prodia executes video jobs synchronously; async operations are not part
/// of its wire protocol.
pub impl @provider.VideoModelV4 for ProdiaVideoModel with fn do_start(
  _self,
  _options,
) -> @provider.VideoModelV4OperationStartResult raise {
  raise @provider.UnsupportedFunctionalityError(
    functionality="Prodia video async operations",
  )
}

///|
pub impl @provider.VideoModelV4 for ProdiaVideoModel with fn do_status(
  _self,
  _call_options,
) -> @provider.VideoModelV4OperationStatusResult raise {
  raise @provider.UnsupportedFunctionalityError(
    functionality="Prodia video async operations",
  )
}

///|
/// Normalized job response shared by the JSON and multipart request paths.
priv struct ProdiaVideoResponse {
  value : Bytes
  content_type : String
  request : @provider.RequestMetadata
  response : @provider.ResponseMetadata
}

///|
pub impl @provider.VideoModelV4 for ProdiaVideoModel with fn do_generate(
  self,
  options,
) {
  let warnings : Array[@provider.Warning] = []
  let resolution = @provider_utils.resolve_provider_options(
    options.provider_options,
    provider_name=self.provider_name,
    aliases=["prodia"],
  )
  for warning in resolution.warnings {
    warnings.push(warning)
  }
  let job_config : Map[String, Json] = Map([])
  if options.prompt is Some(value) {
    job_config["prompt"] = Json::string(value)
  }
  if options.seed is Some(value) {
    job_config["seed"] = Json::number(value.to_double())
  }
  if resolution.values.get("resolution") is Some(value) {
    job_config["resolution"] = value
  }
  let job_fields : Map[String, Json] = Map([
    ("type", Json::string(self.model_id)),
    ("config", Json::object(job_config)),
  ])
  let request_created_at = (@env.now() / 1000UL).to_int()
  let cancellation_token = options.cancellation_token
  let job_json = Json::object(job_fields).stringify()
  let response : ProdiaVideoResponse = match options.image {
    // Image-conditioned generation submits the job as multipart with the
    // input frame attached.
    Some(image) => {
      let (image_bytes, image_media_type) = match image {
        @provider.VideoV4Bytes(data~, media_type~, ..) => (data, media_type)
        @provider.VideoV4Data(data~, media_type~, ..) =>
          (@base64.decode(data), media_type)
        @provider.VideoV4Url(url~, ..) => {
          let downloaded = @provider_utils.download_file(
            provider_name=self.provider_name,
            url~,
            timeout_ms=self.idle_timeout_ms,
            retry_policy=options.retry_policy,
            cancellation_token?,
            trusted_origin=self.base_url,
            transport=self.http_transport,
          )
          (downloaded.data, downloaded.media_type)
        }
      }
      let fields : Array[@provider_utils.MultipartField] = [
        @provider_utils.MultipartField::text(name="job", value=job_json),
        @provider_utils.MultipartField::file(
          name="input",
          filename="input",
          media_type=image_media_type,
          data=image_bytes,
        ),
      ]
      let form_data = @provider_utils.encode_multipart_form_data(fields)
      let posted = @provider_utils.post_multipart_binary(
        provider_name=self.provider_name,
        url=@provider_utils.append_path(self.base_url, "/job?price=true"),
        headers=prodia_request_headers(
          api_key=self.api_key,
          headers=self.headers,
          extra=options.headers,
          content_type=form_data.content_type,
          accept="multipart/form-data; video/mp4",
        ),
        form_data~,
        timeout_ms=self.idle_timeout_ms,
        retry_policy=options.retry_policy,
        cancellation_token?,
        error_to_message=prodia_error_to_message,
        is_retryable_response=(_status_code, _error) => None,
        transport=self.http_transport,
      )
      ProdiaVideoResponse::{
        value: posted.value,
        content_type: posted.response.headers.get("content-type").unwrap_or(""),
        request: posted.request,
        response: posted.response,
      }
    }
    None => {
      let posted = @provider_utils.post_json_binary(
        provider_name=self.provider_name,
        url=@provider_utils.append_path(self.base_url, "/job?price=true"),
        headers=prodia_request_headers(
          api_key=self.api_key,
          headers=self.headers,
          extra=options.headers,
          content_type="application/json",
          accept="multipart/form-data; video/mp4",
        ),
        body=Json::object(job_fields),
        timeout_ms=self.idle_timeout_ms,
        retry_policy=options.retry_policy,
        cancellation_token?,
        error_to_message=prodia_error_to_message,
        is_retryable_response=(_status_code, _error) => None,
        transport=self.http_transport,
      )
      ProdiaVideoResponse::{
        value: posted.value,
        content_type: posted.response.headers.get("content-type").unwrap_or(""),
        request: posted.request,
        response: posted.response,
      }
    }
  }
  let parts = @provider_utils.parse_multipart_response(
    content_type=response.content_type,
    data=response.value,
  )
  let job = decode_prodia_job_part(parts)
  let (video_bytes, media_type) = decode_prodia_video_part(parts)
  @provider.VideoModelV4Result::new(
    [@provider.VideoV4Binary(data=video_bytes, media_type~)],
    warnings~,
    provider_metadata=prodia_job_metadata(job),
    request=response.request,
    response=@provider.merge_response_metadata(
      Some(response.response),
      @provider.ResponseMetadata::new(
        model_id=self.model_id,
        created_at=request_created_at,
      ),
    ),
  )
}
