///|
fn normalize_base64(value : String) -> String {
  let normalized = value
    .replace(old=" ", new="")
    .replace(old="\t", new="")
    .replace(old="\n", new="")
    .replace(old="\r", new="")
    .replace(old="\u{c}", new="")
    .replace(old="-", new="+")
    .replace(old="_", new="/")
  match normalized.length() % 4 {
    2 => normalized + "=="
    3 => normalized + "="
    _ => normalized
  }
}

///|
/// Decode standard or URL-safe Base64 data to MoonBit bytes.
///
/// `Bytes` is the MoonBit counterpart of the AI SDK's `Uint8Array`.
pub fn convert_base64_to_bytes(value : String) -> Bytes raise {
  @base64.decode(normalize_base64(value), ignore_whitespace=true) catch {
    _ => fail("invalid Base64 data")
  }
}

///|
/// AI SDK-style spelling of `convert_base64_to_bytes`.
pub fn convertBase64ToUint8Array(value : String) -> Bytes raise {
  convert_base64_to_bytes(value)
}

///|
/// Encode MoonBit bytes as standard padded Base64 data.
pub fn convert_bytes_to_base64(value : Bytes) -> String {
  @base64.encode(value)
}

///|
/// AI SDK-style spelling of `convert_bytes_to_base64`.
pub fn convertUint8ArrayToBase64(value : Bytes) -> String {
  convert_bytes_to_base64(value)
}

///|
/// Preserve Base64 strings and encode raw bytes from a V4 inline file value.
/// URL, provider-reference, and text variants are not binary inline data.
pub fn convert_to_base64(
  data : @provider.LanguageModelV4FileData,
) -> String raise {
  match data {
    @provider.V4FileData(value) => value
    @provider.V4FileBytes(value) => convert_bytes_to_base64(value)
    @provider.V4FileUrl(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="URL-backed inline file data",
      )
    @provider.V4FileReference(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="provider-reference inline file data",
      )
    @provider.V4FileText(_) =>
      raise @provider.UnsupportedFunctionalityError(
        functionality="text file parts",
      )
  }
}

///|
/// AI SDK-style spelling of `convert_to_base64`.
///
/// MoonBit represents the TypeScript `string | Uint8Array` payload with the
/// data and bytes variants of `LanguageModelV4FileData`.
pub fn convertToBase64(
  data : @provider.LanguageModelV4FileData,
) -> String raise {
  convert_to_base64(data)
}
