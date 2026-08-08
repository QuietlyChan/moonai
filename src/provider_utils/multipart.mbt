///|
/// One value in a multipart/form-data request.
pub(all) enum MultipartValue {
  MultipartText(String)
  MultipartFile(filename~ : String, media_type~ : String, data~ : Bytes)
} derive(Debug, Eq)

///|
/// One named multipart/form-data field.
pub(all) struct MultipartField {
  name : String
  value : MultipartValue
} derive(Debug, Eq)

///|
/// Construct a text form-data field.
pub fn MultipartField::text(name~ : String, value~ : String) -> MultipartField {
  { name, value: MultipartText(value) }
}

///|
/// Construct a binary file form-data field.
pub fn MultipartField::file(
  name~ : String,
  filename~ : String,
  media_type~ : String,
  data~ : Bytes,
) -> MultipartField {
  { name, value: MultipartFile(filename~, media_type~, data~) }
}

///|
/// Encoded multipart/form-data payload and its request metadata representation.
pub(all) struct MultipartFormData {
  boundary : String
  content_type : String
  body : Bytes
  diagnostic_body : String
} derive(Debug, Eq)

///|
/// Binary image input after URL download or base64 decoding.
pub(all) struct ResolvedImageFile {
  filename : String
  media_type : String
  data : Bytes
} derive(Debug, Eq)

///|
/// Resolve a provider-neutral image file into bytes suitable for multipart.
pub async fn resolve_image_file(
  file : @provider.ImageFile,
  provider_name~ : String,
  timeout_ms? : Int = 120_000,
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
  trusted_origin? : String,
  transport? : &HttpTransport,
) -> ResolvedImageFile {
  match file {
    @provider.ImageFileBase64(data~, media_type~, filename~) =>
      {
        filename,
        media_type: resolve_full_media_type(media_type, data),
        data: convert_base64_to_bytes(data),
      }
    @provider.ImageFileBytes(data~, media_type~, filename~) =>
      { filename, media_type, data }
    @provider.ImageFileUrl(url~, filename~) => {
      let downloaded = download_file(
        provider_name~,
        url~,
        timeout_ms~,
        retry_policy~,
        cancellation_token?,
        trusted_origin?,
        transport?,
      )
      { filename, media_type: downloaded.media_type, data: downloaded.data }
    }
  }
}

///|
/// Resolve a V4 image input without lowering it through the legacy image-file
/// representation. Protocol adapters supply the multipart filename because
/// the V4 provider contract intentionally does not carry one.
pub async fn resolve_image_model_v4_file(
  file : @provider.ImageModelV4File,
  filename? : String = "image",
  provider_name~ : String,
  timeout_ms? : Int = 120_000,
  retry_policy? : @provider.RetryPolicy = @provider.RetryPolicy::standard(),
  cancellation_token? : @provider.CancellationToken,
  trusted_origin? : String,
  transport? : &HttpTransport,
) -> ResolvedImageFile {
  match file {
    @provider.ImageV4Data(data~, media_type~) =>
      {
        filename,
        media_type: resolve_full_media_type(media_type, data),
        data: convert_base64_to_bytes(data),
      }
    @provider.ImageV4Bytes(data~, media_type~) => { filename, media_type, data }
    @provider.ImageV4Url(url~) => {
      let downloaded = download_file(
        provider_name~,
        url~,
        timeout_ms~,
        retry_policy~,
        cancellation_token?,
        trusted_origin?,
        transport?,
      )
      { filename, media_type: downloaded.media_type, data: downloaded.data }
    }
  }
}

///|
/// Convert provider-level transcription audio to binary multipart data.
pub fn resolve_transcription_audio(
  audio : @provider.TranscriptionAudio,
) -> Bytes raise {
  match audio {
    @provider.TranscriptionAudioBytes(value) => value
    @provider.TranscriptionAudioBase64(value) =>
      convert_base64_to_bytes(value) catch {
        _ => fail("invalid Base64 transcription audio")
      }
  }
}

///|
/// Map an IANA media type to a conventional upload filename extension.
pub fn media_type_to_extension(media_type : String) -> String {
  let parts = media_type.to_lower().split("/").to_array()
  let subtype = if parts.length() > 1 { parts[1].to_owned() } else { "" }
  match subtype {
    "mpeg" => "mp3"
    "x-wav" => "wav"
    "opus" => "ogg"
    "mp4" | "x-m4a" => "m4a"
    value => value
  }
}

///|
/// AI SDK-style spelling for `media_type_to_extension`.
pub fn mediaTypeToExtension(media_type : String) -> String {
  media_type_to_extension(media_type)
}

///|
fn validate_multipart_token(value : String, label : String) -> Unit raise {
  guard value != "" else { fail("multipart \{label} cannot be empty") }
  guard !value.contains("\r") && !value.contains("\n") && !value.contains("\"") else {
    fail("multipart \{label} contains an invalid header character")
  }
}

///|
fn write_multipart_string(buffer : @buffer.Buffer, value : String) -> Unit {
  buffer.write_string_utf8(value)
}

///|
fn multipart_file_diagnostic(
  name : String,
  filename : String,
  media_type : String,
  byte_length : Int,
) -> String {
  "<file name=\"\{name}\" filename=\"\{filename}\" type=\"\{media_type}\" bytes=\{byte_length}>"
}

///|
fn multipart_bytes_contains(data : Bytes, needle : Bytes) -> Bool {
  if needle.length() == 0 {
    return true
  }
  if data.length() < needle.length() {
    return false
  }
  for start = 0; start <= data.length() - needle.length(); start = start + 1 {
    let mut equal = true
    for offset = 0; offset < needle.length(); offset = offset + 1 {
      if data[start + offset] != needle[offset] {
        equal = false
        break
      }
    }
    if equal {
      return true
    }
  }
  false
}

///|
fn multipart_fields_contain_boundary(
  fields : Array[MultipartField],
  boundary : String,
) -> Bool {
  let boundary_bytes = @utf8.encode(boundary)
  for field in fields {
    match field.value {
      MultipartText(value) if value.contains(boundary) => return true
      MultipartFile(data~, ..) if multipart_bytes_contains(data, boundary_bytes) =>
        return true
      _ => ()
    }
  }
  false
}

///|
/// Encode ordered fields as an RFC 7578 multipart/form-data request body.
pub fn encode_multipart_form_data(
  fields : Array[MultipartField],
  boundary? : String = "moonai-7MA4YWxkTrZu0gW",
) -> MultipartFormData raise {
  validate_multipart_token(boundary, "boundary")
  let mut resolved_boundary = boundary
  while multipart_fields_contain_boundary(fields, resolved_boundary) {
    resolved_boundary = resolved_boundary + "x"
  }
  let body = @buffer.Buffer()
  let diagnostic = StringBuilder::new()
  for field in fields {
    validate_multipart_token(field.name, "field name")
    write_multipart_string(body, "--\{resolved_boundary}\r\n")
    diagnostic.write_string("--\{resolved_boundary}\r\n")
    match field.value {
      MultipartText(value) => {
        let disposition = "Content-Disposition: form-data; name=\"\{field.name}\"\r\n\r\n"
        write_multipart_string(body, disposition)
        write_multipart_string(body, value)
        write_multipart_string(body, "\r\n")
        diagnostic.write_string(disposition)
        diagnostic.write_string(value)
        diagnostic.write_string("\r\n")
      }
      MultipartFile(filename~, media_type~, data~) => {
        validate_multipart_token(filename, "filename")
        validate_multipart_token(media_type, "media type")
        let disposition = "Content-Disposition: form-data; name=\"\{field.name}\"; filename=\"\{filename}\"\r\n"
        let content_type = "Content-Type: \{media_type}\r\n\r\n"
        write_multipart_string(body, disposition)
        write_multipart_string(body, content_type)
        body.write_bytes(data)
        write_multipart_string(body, "\r\n")
        diagnostic.write_string(disposition)
        diagnostic.write_string(content_type)
        diagnostic.write_string(
          multipart_file_diagnostic(
            field.name,
            filename,
            media_type,
            data.length(),
          ),
        )
        diagnostic.write_string("\r\n")
      }
    }
  }
  write_multipart_string(body, "--\{resolved_boundary}--\r\n")
  diagnostic.write_string("--\{resolved_boundary}--\r\n")
  {
    boundary: resolved_boundary,
    content_type: "multipart/form-data; boundary=\{resolved_boundary}",
    body: body.to_bytes(),
    diagnostic_body: diagnostic.to_string(),
  }
}
