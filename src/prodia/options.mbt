///|
/// Prodia image model ids, e.g. `flux_dev_v1p1`, `sd3.5_large`,
/// `sdxl_v1.0` (the id becomes the job `type` field).
pub type ProdiaImageModelId = String

///|
/// Prodia video model ids, e.g. `prodia_video_v1` (the id becomes the job
/// `type` field).
pub type ProdiaVideoModelId = String

///|
/// Provider options accepted under the `prodia` namespace (all optional):
/// image — `width`, `height`, `steps`, `style_preset`, `negative_prompt`,
/// `guidance_scale`, `num_inference_steps`; video — `resolution`.
