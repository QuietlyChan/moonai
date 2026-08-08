///|
test "image model files convert to URLs and data URIs" {
  assert_eq(
    convert_image_model_file_to_data_uri(
      @provider.ImageModelV4File::url(
        "https://example.com/image.png?width=100&height=200",
      ),
    ),
    "https://example.com/image.png?width=100&height=200",
  )
  assert_eq(
    convert_image_model_file_to_data_uri(
      @provider.ImageModelV4File::base64(
        data="aW1hZ2U=",
        media_type="image/jpeg",
      ),
    ),
    "data:image/jpeg;base64,aW1hZ2U=",
  )
  assert_eq(
    convertImageModelFileToDataUri(
      @provider.ImageModelV4File::bytes(data=b"Hello", media_type="image/webp"),
    ),
    "data:image/webp;base64,SGVsbG8=",
  )
}

///|
test "video model files share the data URI conversion contract" {
  assert_eq(
    convert_video_model_file_to_data_uri(
      @provider.VideoModelV4File::url(
        "https://example.com/reference.mp4",
        media_type="video/mp4",
      ),
    ),
    "https://example.com/reference.mp4",
  )
  assert_eq(
    convert_video_model_file_to_data_uri(
      @provider.VideoModelV4File::base64(
        data="dmlkZW8=",
        media_type="video/mp4",
      ),
    ),
    "data:video/mp4;base64,dmlkZW8=",
  )
  assert_eq(
    convertVideoModelFileToDataUri(
      @provider.VideoModelV4File::bytes(data=b"video", media_type="video/mp4"),
    ),
    "data:video/mp4;base64,dmlkZW8=",
  )
}
