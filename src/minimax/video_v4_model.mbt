///|
/// AI SDK-aligned V4 surface for MiniMax's asynchronous video endpoint.
pub impl @provider.VideoModelV4 for MiniMaxVideoModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.VideoModelV4 for MiniMaxVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
pub impl @provider.VideoModelV4 for MiniMaxVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
pub impl @provider.VideoModelV4 for MiniMaxVideoModel with fn max_videos_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
pub impl @provider.VideoModelV4 for MiniMaxVideoModel with fn do_generate(
  self,
  options,
) {
  @provider.VideoModelV4Result::from_video_response(
    self.generate_video(options.to_video_call_options()),
  )
}
