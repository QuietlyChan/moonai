///|
/// One file in an uploaded provider skill.
pub(all) struct SkillFile {
  path : String
  data : UploadFileData
} derive(Debug, Eq)

///|
/// Construct one skill file relative to the skill root.
pub fn SkillFile::new(path~ : String, data~ : UploadFileData) -> SkillFile {
  { path, data }
}

///|
/// Provider-level options for uploading one skill bundle.
pub(all) struct SkillUploadOptions {
  files : Array[SkillFile]
  display_title : String?
  provider_options : Map[String, Json]
} derive(Debug, Eq)

///|
/// Construct one skill upload call.
pub fn SkillUploadOptions::new(
  files~ : Array[SkillFile],
  display_title? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> SkillUploadOptions {
  { files, display_title, provider_options }
}

///|
/// Result returned after a provider accepts a skill bundle.
pub(all) struct SkillUploadResult {
  provider_reference : ProviderReference
  display_title : String?
  name : String?
  description : String?
  latest_version : String?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
} derive(Debug, Eq)

///|
/// Construct a provider skill-upload result.
pub fn SkillUploadResult::new(
  provider_reference~ : ProviderReference,
  display_title? : String,
  name? : String,
  description? : String,
  latest_version? : String,
  provider_metadata? : Map[String, Json] = Map([]),
  warnings? : Array[Warning] = [],
) -> SkillUploadResult {
  {
    provider_reference,
    display_title,
    name,
    description,
    latest_version,
    provider_metadata: copy_provider_metadata(provider_metadata),
    warnings: copy_warnings(warnings),
  }
}
