///|
/// Deterministic image generation model for SDK consumer tests.
pub struct MockImageModel {
  priv provider_name : String
  priv model_id : String
  priv max_images : Int
  priv result : @provider.ImageResponse
  priv captured_batch_sizes : Array[Int]
}

///|
/// Construct a deterministic image model.
pub fn MockImageModel::new(
  result : @provider.ImageResponse,
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
pub impl @provider.ImageWireModel for MockImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageWireModel for MockImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageWireModel for MockImageModel with fn max_images_per_call(
  self,
) -> Int {
  self.max_images
}

///|
pub impl @provider.ImageWireModel for MockImageModel with fn generate(
  self,
  options,
) {
  self.generate_images(options)
}

///|
fn MockImageModel::generate_images(
  self : MockImageModel,
  options : @provider.ImageCallOptions,
) -> @provider.ImageResponse {
  self.captured_batch_sizes.push(options.n)
  guard self.result.images.length() > 0 else { self.result }
  let images : Array[@provider.GeneratedImage] = []
  let mut index = 0
  while index < options.n {
    images.push(self.result.images[index % self.result.images.length()])
    index = index + 1
  }
  @provider.ImageResponse::new(images, self.result.usage).with_diagnostics(
    self.result.request,
    self.result.response,
    self.result.provider_metadata,
    self.result.warnings,
  )
}

///|
pub impl @provider.ImageModelV4 for MockImageModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.ImageModelV4 for MockImageModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.ImageModelV4 for MockImageModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.ImageModelV4 for MockImageModel with fn max_images_per_call(
  self,
) -> Int? {
  Some(self.max_images)
}

///|
pub impl @provider.ImageModelV4 for MockImageModel with fn do_generate(
  self,
  options,
) {
  let files : Array[@provider.ImageFile] = match options.files {
    Some(values) => [ for file in values => file.to_image_file() ]
    None => []
  }
  let mask = match options.mask {
    Some(value) => Some(value.to_image_file(filename="mask"))
    None => None
  }
  @provider.ImageModelV4Result::from_image_response(
    self.generate_images(
      @provider.ImageCallOptions::new(
        options.prompt.unwrap_or(""),
        n=options.n,
        size?=options.size,
        aspect_ratio?=options.aspect_ratio,
        seed?=options.seed,
        files~,
        mask?,
        headers=options.headers,
        provider_options=options.provider_options,
        retry_policy=options.retry_policy,
        cancellation_token?=options.cancellation_token,
      ),
    ),
  )
}
