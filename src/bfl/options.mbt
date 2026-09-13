///|
/// Black Forest Labs image model ids, e.g. `flux-pro-v1.1`,
/// `flux-kontext-pro`, `flux-dev`.
pub type BflImageModelId = String

///|
/// Default polling interval between status checks.
pub const BFL_POLL_INTERVAL_MS : Int = 500

///|
/// Default overall polling timeout before giving up.
pub const BFL_POLL_TIMEOUT_MS : Int = 60_000

///|
/// Provider options accepted under the `bfl` namespace (all optional, wire
/// names as given): `width`, `height`, `prompt_upsampling`, `safety_tolerance`,
/// `output_format`, `raw`, `image_prompt`, `input_image` (Kontext editing).
