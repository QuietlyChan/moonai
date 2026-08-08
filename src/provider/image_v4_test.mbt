///|
test "legacy image calls lift losslessly into V4 options" {
  let v4 = ImageModelV4CallOptions::from_image_call_options(
    ImageCallOptions::new(
      "Edit",
      n=2,
      size="1024x1024",
      files=[
        ImageFile::bytes(
          data=b"image",
          media_type="image/png",
          filename="input.png",
        ),
      ],
      mask=ImageFile::base64(
        data="bWFzaw==",
        media_type="image/png",
        filename="mask.png",
      ),
      headers={ "X-Test": "yes" },
    ),
  )
  assert_eq(v4.prompt, Some("Edit"))
  assert_eq(v4.n, 2)
  assert_eq(v4.size, Some("1024x1024"))
  assert_eq(v4.headers.get("X-Test"), Some("yes"))
  match v4.files {
    Some([ImageV4Bytes(data~, media_type~)]) => {
      assert_eq(data, b"image")
      assert_eq(media_type, "image/png")
    }
    _ => fail("expected a byte-backed V4 image")
  }
  assert_true(
    v4.mask is Some(ImageV4Data(data="bWFzaw==", media_type="image/png")),
  )
}

///|
test "empty legacy image file lists remain absent at the V4 boundary" {
  let v4 = ImageModelV4CallOptions::from_image_call_options(
    ImageCallOptions::new("Generate"),
  )
  assert_eq(v4.files, None)
  assert_eq(v4.mask, None)
}
