///|
/// Luma Dream Machine image model ids, e.g. `photon-1`, `photon-flash-1`.
pub type LumaImageModelId = String

///|
/// Default polling interval for generation status checks.
pub const LUMA_POLL_INTERVAL_MS : Int = 3000

///|
/// Default maximum poll attempts before giving up.
pub const LUMA_MAX_POLL_ATTEMPTS : Int = 60

///|
/// Provider options accepted under the `luma` namespace (all optional):
/// `model` override, `image_reference` entries (`{ url, weight }` arrays
/// keyed by reference type), `character` identities, `modify_image`.
