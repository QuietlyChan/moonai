///|
/// Official OpenAI Skills API implementation.
pub struct OpenAISkills {
  priv provider_name : String
  priv base_url : String
  priv api_key : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
fn openai_skills(
  provider_name~ : String,
  base_url~ : String,
  api_key~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> OpenAISkills {
  {
    provider_name: "\{provider_name}.skills",
    base_url: @provider_utils.without_trailing_slash(base_url),
    api_key,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
  }
}

///|
fn OpenAISkills::url(self : OpenAISkills) -> String {
  @provider_utils.append_path(self.base_url, "/skills")
}

///|
fn OpenAISkills::request_headers(
  self : OpenAISkills,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([("Accept-Encoding", "identity")])
  headers["Authorization"] = "Bearer \{load_openai_api_key(self.api_key)}"
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(headers, self.headers),
    ["moonai/openai/\{VERSION}"],
  )
}

///|
fn OpenAISkills::form_data(
  _self : OpenAISkills,
  call_options : @provider.SkillUploadOptions,
) -> @provider_utils.MultipartFormData raise {
  let fields : Array[@provider_utils.MultipartField] = []
  for file in call_options.files {
    fields.push(
      @provider_utils.MultipartField::file(
        name="files[]",
        filename=file.path,
        media_type="application/octet-stream",
        data=@provider_utils.resolve_upload_file_data(file.data),
      ),
    )
  }
  @provider_utils.encode_multipart_form_data(fields)
}

///|
fn openai_skills_provider_metadata(json : Json) -> Map[String, Json] {
  let fields : Map[String, Json] = Map([])
  match json {
    { "default_version": String(value), .. } =>
      fields["defaultVersion"] = Json::string(value)
    _ => ()
  }
  match json {
    { "created_at": Number(value, ..), .. } =>
      fields["createdAt"] = Json::number(value)
    _ => ()
  }
  match json {
    { "updated_at": Number(value, ..), .. } =>
      fields["updatedAt"] = Json::number(value)
    _ => ()
  }
  Map([("openai", Json::object(fields))])
}

///|
fn decode_openai_skill_upload(
  json : Json,
  warnings : Array[@provider.Warning],
) -> @provider.SkillUploadResult raise {
  if openai_error_message(json) is Some(message) {
    raise @provider.InvalidResponseDataError(
      message="OpenAI Skills request failed: \{message}",
      data=json,
    )
  }
  let id = match json {
    { "id": String(value), .. } => value
    _ =>
      raise @provider.InvalidResponseDataError(
        message="OpenAI Skills response has no skill id",
        data=json,
      )
  }
  let name = match json {
    { "name": String(value), .. } => Some(value)
    _ => None
  }
  let description = match json {
    { "description": String(value), .. } => Some(value)
    _ => None
  }
  let latest_version = match json {
    { "latest_version": String(value), .. } => Some(value)
    _ => None
  }
  @provider.SkillUploadResult::new(
    provider_reference=@provider.ProviderReference::single(
      provider="openai",
      id~,
    ),
    name?,
    description?,
    latest_version?,
    provider_metadata=openai_skills_provider_metadata(json),
    warnings~,
  )
}

///|
async fn OpenAISkills::upload(
  self : OpenAISkills,
  call_options : @provider.SkillUploadOptions,
) -> @provider.SkillUploadResult {
  let warnings : Array[@provider.Warning] = []
  if call_options.display_title is Some(_) {
    warnings.push(@provider.Warning::unsupported("displayTitle"))
  }
  let response = @provider_utils.post_multipart(
    provider_name=self.provider_name,
    url=self.url(),
    headers=self.request_headers(),
    form_data=self.form_data(call_options),
    timeout_ms=self.idle_timeout_ms,
    error_to_message=openai_error_message,
    transport=self.http_transport,
  )
  decode_openai_skill_upload(response.value, warnings)
}

///|
pub impl @provider.Skills for OpenAISkills with fn provider(self : OpenAISkills) -> String {
  self.provider_name
}

///|
pub impl @provider.Skills for OpenAISkills with fn upload_skill(
  self : OpenAISkills,
  call_options : @provider.SkillUploadOptions,
) -> @provider.SkillUploadResult {
  self.upload(call_options)
}
