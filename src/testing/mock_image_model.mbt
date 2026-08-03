///|
/// Deterministic image generation model for SDK consumer tests.
pub struct MockImageModel {
  priv provider_name : String
  priv model_id : String
  priv max_images : Int
  priv result : @moonai.ImageResponse
  priv captured_batch_sizes : Array[Int]
}

///|
/// Construct a deterministic image model.
pub fn MockImageModel::new(
  result : @moonai.ImageResponse,
  max_images_per_call? : Int = 10,
  provider_name? : String = "mock",
  model_id? : String = "mock-image-model",
) -> MockImageModel {
  {
    provider_name,
    model_id,
    max_images: max_images_per_call,
    result,
    captured_batch_sizes: [],
  }
}

///|
/// Return requested batch sizes in call order.
pub fn MockImageModel::captured_batch_sizes(
  self : MockImageModel,
) -> Array[Int] {
  self.captured_batch_sizes.copy()
}

///|
pub impl @moonai.ImageModel for MockImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @moonai.ImageModel for MockImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @moonai.ImageModel for MockImageModel with fn max_images_per_call(self) -> Int {
  self.max_images
}

///|
pub impl @moonai.ImageModel for MockImageModel with fn generate(self, options) {
  self.captured_batch_sizes.push(options.n)
  guard self.result.images.length() > 0 else { self.result }
  let images : Array[@moonai.GeneratedImage] = []
  let mut index = 0
  while index < options.n {
    images.push(self.result.images[index % self.result.images.length()])
    index = index + 1
  }
  @moonai.ImageResponse::new(images, self.result.usage).with_diagnostics(
    self.result.request,
    self.result.response,
    self.result.provider_metadata,
    self.result.warnings,
  )
}
