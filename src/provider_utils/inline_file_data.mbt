///|
/// Convert provider-level inline upload data to raw bytes.
pub fn convert_inline_file_data_to_bytes(
  data : @provider.UploadFileData,
) -> Bytes raise {
  match data {
    @provider.UploadFileBytes(value) => value
    @provider.UploadFileBase64(value) => convert_base64_to_bytes(value)
    @provider.UploadFileText(value) => @utf8.encode(value)
  }
}

///|
/// AI SDK-style spelling of `convert_inline_file_data_to_bytes`.
///
/// The return type is `Bytes`, MoonBit's counterpart of `Uint8Array`.
pub fn convertInlineFileDataToUint8Array(
  data : @provider.UploadFileData,
) -> Bytes raise {
  convert_inline_file_data_to_bytes(data)
}
