///|
/// Anthropic Skills API implementation.
pub struct AnthropicSkills {
  priv provider_name : String
  priv base_url : String
  priv api_key : String
  priv auth_token : String
  priv api_key_environment_variable : String?
  priv anthropic_version : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
fn anthropic_skills_provider_name(provider_name : String) -> String {
  let base = provider_name
    .strip_suffix(".messages")
    .unwrap_or(provider_name)
    .to_owned()
  "\{base}.skills"
}

///|
fn anthropic_skills(
  provider_name~ : String,
  base_url~ : String,
  api_key~ : String,
  auth_token~ : String,
  anthropic_version~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
  api_key_environment_variable~ : String?,
) -> AnthropicSkills {
  {
    provider_name: anthropic_skills_provider_name(provider_name),
    base_url: normalize_base_url(base_url),
    api_key,
    auth_token,
    api_key_environment_variable,
    anthropic_version,
    headers: @provider_utils.copy_headers(headers),
    idle_timeout_ms,
    http_transport,
  }
}

///|
/// Select the Skills API from an Anthropic provider factory.
pub fn AnthropicProvider::skills(self : AnthropicProvider) -> AnthropicSkills {
  anthropic_skills(
    provider_name=self.provider_name,
    base_url=self.base_url,
    api_key=self.api_key,
    auth_token=self.auth_token,
    anthropic_version=self.anthropic_version,
    headers=self.headers,
    idle_timeout_ms=self.idle_timeout_ms,
    http_transport=self.http_transport,
    api_key_environment_variable=self.api_key_environment_variable,
  )
}

///|
fn AnthropicSkills::skills_url(self : AnthropicSkills) -> String {
  @provider_utils.append_path(self.base_url, "/skills")
}

///|
fn AnthropicSkills::version_url(
  self : AnthropicSkills,
  skill_id : String,
  version : String,
) -> String {
  @provider_utils.append_path(
    self.base_url,
    "/skills/\{skill_id}/versions/\{version}",
  )
}

///|
fn AnthropicSkills::request_headers(
  self : AnthropicSkills,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let headers : Map[String, String] = Map([])
  headers["Accept-Encoding"] = "identity"
  headers["anthropic-version"] = self.anthropic_version
  for
    entry in anthropic_authentication_headers(
      self.api_key,
      self.auth_token,
      self.api_key_environment_variable,
    ).iter2() {
    let (key, value) = entry
    headers[key] = value
  }
  let merged = @provider_utils.merge_headers(headers, self.headers)
  merged["anthropic-beta"] = "skills-2025-10-02"
  @provider_utils.with_user_agent_suffix(merged, ["moonai/anthropic/\{VERSION}"])
}

///|
fn AnthropicSkills::form_data(
  _self : AnthropicSkills,
  options : @provider.SkillUploadOptions,
) -> @provider_utils.MultipartFormData raise {
  let fields : Array[@provider_utils.MultipartField] = []
  if options.display_title is Some(display_title) {
    fields.push(
      @provider_utils.MultipartField::text(
        name="display_title",
        value=display_title,
      ),
    )
  }
  for file in options.files {
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
fn anthropic_skill_required_string(
  json : Json,
  field : String,
  description : String,
) -> String raise {
  match json {
    Object(values) =>
      match values.get(field) {
        Some(String(value)) => value
        _ =>
          raise @provider.InvalidResponseDataError(
            message="Anthropic Skills response has no \{description}",
            data=json,
          )
      }
    _ =>
      raise @provider.InvalidResponseDataError(
        message="Anthropic Skills response has no \{description}",
        data=json,
      )
  }
}

///|
fn anthropic_skill_optional_string(json : Json, field : String) -> String? {
  match json {
    Object(values) =>
      match values.get(field) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn anthropic_skill_provider_metadata(json : Json) -> Map[String, Json] raise {
  let source = anthropic_skill_required_string(json, "source", "source")
  let created_at = anthropic_skill_required_string(
    json, "created_at", "created_at",
  )
  let updated_at = anthropic_skill_required_string(
    json, "updated_at", "updated_at",
  )
  Map([
    (
      "anthropic",
      { "source": source, "createdAt": created_at, "updatedAt": updated_at },
    ),
  ])
}

///|
async fn AnthropicSkills::fetch_version_metadata(
  self : AnthropicSkills,
  skill_id : String,
  version : String,
) -> (String?, String?) {
  let response = @provider_utils.get_json(
    provider_name=self.provider_name,
    url=self.version_url(skill_id, version),
    headers=self.request_headers(),
    timeout_ms=self.idle_timeout_ms,
    error_to_message=anthropic_error_message,
    transport=self.http_transport,
  )
  let _ = anthropic_skill_required_string(
    response.value,
    "type",
    "version type",
  )
  let _ = anthropic_skill_required_string(
    response.value,
    "skill_id",
    "version skill_id",
  )
  (
    anthropic_skill_optional_string(response.value, "name"),
    anthropic_skill_optional_string(response.value, "description"),
  )
}

///|
async fn AnthropicSkills::upload(
  self : AnthropicSkills,
  options : @provider.SkillUploadOptions,
) -> @provider.SkillUploadResult {
  let response = @provider_utils.post_multipart(
    provider_name=self.provider_name,
    url=self.skills_url(),
    headers=self.request_headers(),
    form_data=self.form_data(options),
    timeout_ms=self.idle_timeout_ms,
    error_to_message=anthropic_error_message,
    transport=self.http_transport,
  )
  let id = anthropic_skill_required_string(response.value, "id", "skill id")
  let display_title = anthropic_skill_optional_string(
    response.value,
    "display_title",
  )
  let latest_version = anthropic_skill_optional_string(
    response.value,
    "latest_version",
  )
  let mut name = anthropic_skill_optional_string(response.value, "name")
  let mut description = anthropic_skill_optional_string(
    response.value,
    "description",
  )
  if latest_version is Some(version) {
    let (version_name, version_description) = self.fetch_version_metadata(
      id, version,
    )
    if version_name is Some(value) {
      name = Some(value)
    }
    if version_description is Some(value) {
      description = Some(value)
    }
  }
  @provider.SkillUploadResult::new(
    provider_reference=@provider.ProviderReference::single(
      provider="anthropic",
      id~,
    ),
    display_title?,
    name?,
    description?,
    latest_version?,
    provider_metadata=anthropic_skill_provider_metadata(response.value),
    warnings=[],
  )
}

///|
pub impl @provider.Skills for AnthropicSkills with fn provider(
  self : AnthropicSkills,
) -> String {
  self.provider_name
}

///|
pub impl @provider.Skills for AnthropicSkills with fn upload_skill(
  self : AnthropicSkills,
  options : @provider.SkillUploadOptions,
) -> @provider.SkillUploadResult {
  self.upload(options)
}
