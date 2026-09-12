///|
/// Convert provider-level inline upload data to raw bytes.
///
/// Streaming upload data cannot be converted synchronously; use
/// `collect_upload_file_data` in async contexts.
pub fn convert_inline_file_data_to_bytes(
  data : @provider.UploadFileData,
) -> Bytes raise {
  match data {
    @provider.UploadFileBytes(value) => value
    @provider.UploadFileBase64(value) => convert_base64_to_bytes(value)
    @provider.UploadFileText(value) => @utf8.encode(value)
    @provider.UploadFileStream(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="streaming upload data in a synchronous conversion",
      )
  }
}

///|
/// Collect provider-level inline upload data as raw bytes.
///
/// Streaming upload data is drained chunk by chunk into a single buffer;
/// buffered variants are returned unchanged.
pub async fn collect_upload_file_data(data : @provider.UploadFileData) -> Bytes {
  match data {
    @provider.UploadFileStream(stream) => {
      // Drained into one buffer today; wire-level streaming lands together
      // with incremental request-body transport support.
      let mut buffer : Bytes = b""
      for ;; {
        @provider.check_cancellation(None)
        match stream.read_chunk() {
          Some(chunk) => buffer = buffer + chunk
          None => break
        }
      }
      buffer
    }
    other => convert_inline_file_data_to_bytes(other)
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
