///|
/// fal model ids, e.g. `fal-ai/flux-pro/v1.1/text-to-image` (the model id
/// doubles as the request path under https://fal.run).
pub type FalImageModelId = String

///|
/// Provider options accepted under the `fal` namespace (all optional, wire
/// names as given): `image_size` (`{ width, height }` or named presets),
/// `num_inference_steps`, `guidance_scale`, `enable_safety_checker`,
/// `output_format`.
