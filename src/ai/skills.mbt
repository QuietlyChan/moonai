///|
/// Upload a provider skill bundle.
pub async fn upload_skill(
  skills : &SkillsV4,
  files~ : Array[SkillsV4File],
  display_title? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> SkillsV4UploadSkillResult {
  guard files.length() > 0 else {
    fail("upload_skill requires at least one file")
  }
  for file in files {
    guard file.path.trim() != "" else {
      fail("upload_skill file paths cannot be empty")
    }
  }
  skills.upload_skill(
    SkillsV4UploadSkillCallOptions::new(
      files~,
      display_title?,
      provider_options~,
    ),
  )
}

///|
/// AI SDK-style camel-case spelling for `upload_skill`.
pub async fn uploadSkill(
  skills : &SkillsV4,
  files~ : Array[SkillsV4File],
  display_title? : String,
  provider_options? : Map[String, Json] = Map([]),
) -> SkillsV4UploadSkillResult {
  upload_skill(skills, files~, display_title?, provider_options~)
}
