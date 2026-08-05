///|
/// Deterministic video generation model for SDK consumer tests.
pub struct MockVideoModel {
  priv provider_name : String
  priv model_id : String
  priv max_videos : Int
  priv result : @provider.VideoResponse
  priv captured_batch_sizes : Array[Int]
}

///|
/// Construct a deterministic video model.
pub fn MockVideoModel::new(
  result : @provider.VideoResponse,
  max_videos_per_call? : Int = 1,
  provider_name? : String = "mock",
  model_id? : String = "mock-video-model",
) -> MockVideoModel {
  {
    provider_name,
    model_id,
    max_videos: max_videos_per_call,
    result,
    captured_batch_sizes: [],
  }
}

///|
/// Return requested batch sizes in call order.
pub fn MockVideoModel::captured_batch_sizes(
  self : MockVideoModel,
) -> Array[Int] {
  self.captured_batch_sizes.copy()
}

///|
pub impl @provider.VideoWireModel for MockVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.VideoWireModel for MockVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.VideoWireModel for MockVideoModel with fn max_videos_per_call(
  self,
) -> Int {
  self.max_videos
}

///|
pub impl @provider.VideoWireModel for MockVideoModel with fn generate(
  self,
  options,
) {
  self.captured_batch_sizes.push(options.n)
  self.result
}

///|
/// Expose the same deterministic model through the versioned video contract.
pub impl @provider.VideoModelV4 for MockVideoModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.VideoModelV4 for MockVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.VideoModelV4 for MockVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.VideoModelV4 for MockVideoModel with fn max_videos_per_call(
  self,
) -> Int? {
  Some(self.max_videos)
}

///|
pub impl @provider.VideoModelV4 for MockVideoModel with fn do_generate(
  self,
  options,
) {
  self.captured_batch_sizes.push(options.n)
  let videos : Array[@provider.VideoModelV4VideoData] = []
  if self.result.videos.length() > 0 {
    for index = 0; index < options.n; index = index + 1 {
      let source = self.result.videos[index % self.result.videos.length()]
      match source.data {
        @provider.Url(value) =>
          videos.push(
            @provider.VideoModelV4VideoData::VideoV4Url(
              url=value,
              media_type=source.media_type,
            ),
          )
        @provider.Base64(value) =>
          videos.push(
            @provider.VideoModelV4VideoData::VideoV4Base64(
              data=value,
              media_type=source.media_type,
            ),
          )
        @provider.Binary(value) =>
          videos.push(
            @provider.VideoModelV4VideoData::VideoV4Binary(
              data=value,
              media_type=source.media_type,
            ),
          )
      }
    }
  }
  @provider.VideoModelV4Result::new(
    videos,
    warnings=self.result.warnings,
    provider_metadata=self.result.provider_metadata,
    request?=self.result.request,
    response?=self.result.response,
  )
}
