///|
/// AI SDK-aligned V4 surface for MiniMax's asynchronous video endpoint.
impl @provider.VideoModelV4 for MiniMaxVideoModel with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
impl @provider.VideoModelV4 for MiniMaxVideoModel with fn provider(self) -> String {
  self.provider_name
}

///|
impl @provider.VideoModelV4 for MiniMaxVideoModel with fn model_id(self) -> String {
  self.model_id
}

///|
impl @provider.VideoModelV4 for MiniMaxVideoModel with fn max_videos_per_call(
  _self,
) -> Int? {
  Some(1)
}

///|
impl @provider.VideoModelV4 for MiniMaxVideoModel with fn do_generate(
  self,
  options,
) {
  self.generate_video_v4(options)
}
