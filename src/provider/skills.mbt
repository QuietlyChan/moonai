///|
/// One file in an uploaded provider skill.
#derive(Debug)
pub(all) struct SkillsV4File {
  path : String
  data : UploadFileData
}

///|
/// Construct one skill file relative to the skill root.
pub fn SkillsV4File::new(
  path~ : String,
  data~ : UploadFileData,
) -> SkillsV4File {
  { path, data, }
}

///|
/// Provider-level options for uploading one skill bundle.
#derive(Debug)
pub(all) struct SkillsV4UploadSkillCallOptions {
  files : Array[SkillsV4File]
  display_title : String?
  provider_options : Map[String, Json]
}

///|
/// Construct one skill upload call.
pub fn SkillsV4UploadSkillCallOptions::new(
  files~ : Array[SkillsV4File],
  display_title? : String,
  provider_options~ : Map[String, Json] = Map([]),
) -> SkillsV4UploadSkillCallOptions {
  { files, display_title, provider_options, }
}

///|
/// Result returned after a provider accepts a skill bundle.
#derive(Debug, Eq)
pub(all) struct SkillsV4UploadSkillResult {
  provider_reference : ProviderReference
  display_title : String?
  name : String?
  description : String?
  latest_version : String?
  provider_metadata : Map[String, Json]
  warnings : Array[Warning]
}

///|
/// Construct a provider skill-upload result.
pub fn SkillsV4UploadSkillResult::new(
  provider_reference~ : ProviderReference,
  display_title? : String,
  name? : String,
  description? : String,
  latest_version? : String,
  provider_metadata~ : Map[String, Json] = Map([]),
  warnings~ : Array[Warning] = [],
) -> SkillsV4UploadSkillResult {
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

///|
#deprecated
pub extend SkillsV4File with Debug::{to_repr}

///|
#deprecated
pub extend SkillsV4UploadSkillCallOptions with Debug::{to_repr}

///|
#deprecated
pub extend SkillsV4UploadSkillResult with Debug::{to_repr}

///|
#deprecated
pub extend SkillsV4UploadSkillResult with Eq::{not_equal, equal}
