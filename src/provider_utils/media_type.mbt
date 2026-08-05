///|
/// Return the top-level segment of an IANA media type.
pub fn get_top_level_media_type(media_type : String) -> String {
  match media_type.find("/") {
    Some(index) => media_type[:index].to_owned()
    None => media_type
  }
}

///|
/// Return whether a media type contains a concrete non-wildcard subtype.
pub fn is_full_media_type(media_type : String) -> Bool {
  match media_type.find("/") {
    Some(index) => {
      let subtype = media_type[index + 1:]
      subtype != "" && subtype != "*"
    }
    None => false
  }
}

///|
fn bytes_match(bytes : BytesView, signature : Array[Int]) -> Bool {
  if bytes.length() < signature.length() {
    return false
  }
  for index, expected in signature {
    if expected >= 0 && bytes[index].to_int() != expected {
      return false
    }
  }
  true
}

///|
fn decoded_signature_prefix(data : String, max_bytes : Int) -> Bytes {
  // Decode only the bounded prefix needed by the signature table. Four Base64
  // characters encode three bytes, so round up to a complete quartet.
  let max_chars = (max_bytes + 2) / 3 * 4
  let end = if data.length() < max_chars { data.length() } else { max_chars }
  let prefix = data[:end].replace(old="-", new="+").replace(old="_", new="/")
  @base64.decode_lossy(prefix)
}

///|
fn id3_tag_length(bytes : BytesView) -> Int? {
  if bytes.length() < 10 ||
    bytes[0].to_int() != 0x49 ||
    bytes[1].to_int() != 0x44 ||
    bytes[2].to_int() != 0x33 {
    return None
  }
  // ID3v2 uses a 7-bit-per-byte sync-safe size for the tag body.
  let size = (bytes[6].to_int() & 0x7f) * 0x200000 +
    (bytes[7].to_int() & 0x7f) * 0x4000 +
    (bytes[8].to_int() & 0x7f) * 0x80 +
    (bytes[9].to_int() & 0x7f)
  Some(size + 10)
}

///|
fn detect_image_media_type(bytes : BytesView) -> String? {
  if bytes_match(bytes, [0x47, 0x49, 0x46]) {
    Some("image/gif")
  } else if bytes_match(bytes, [0x89, 0x50, 0x4e, 0x47]) {
    Some("image/png")
  } else if bytes_match(bytes, [0xff, 0xd8]) {
    Some("image/jpeg")
  } else if bytes_match(bytes, [
      0x52, 0x49, 0x46, 0x46, -1, -1, -1, -1, 0x57, 0x45, 0x42, 0x50,
    ]) {
    Some("image/webp")
  } else if bytes_match(bytes, [0x42, 0x4d]) {
    Some("image/bmp")
  } else if bytes_match(bytes, [0x49, 0x49, 0x2a, 0x00]) ||
    bytes_match(bytes, [0x4d, 0x4d, 0x00, 0x2a]) {
    Some("image/tiff")
  } else if bytes_match(bytes, [
      0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66,
    ]) {
    Some("image/avif")
  } else if bytes_match(bytes, [
      0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63,
    ]) {
    Some("image/heic")
  } else {
    None
  }
}

///|
fn detect_application_media_type(bytes : BytesView) -> String? {
  if bytes_match(bytes, [0x25, 0x50, 0x44, 0x46]) {
    Some("application/pdf")
  } else {
    None
  }
}

///|
fn detect_audio_media_type(bytes : BytesView, include_mp4 : Bool) -> String? {
  if bytes_match(bytes, [0xff, 0xfb]) ||
    bytes_match(bytes, [0xff, 0xfa]) ||
    bytes_match(bytes, [0xff, 0xf3]) ||
    bytes_match(bytes, [0xff, 0xf2]) ||
    bytes_match(bytes, [0xff, 0xe3]) ||
    bytes_match(bytes, [0xff, 0xe2]) {
    Some("audio/mpeg")
  } else if bytes_match(bytes, [
      0x52, 0x49, 0x46, 0x46, -1, -1, -1, -1, 0x57, 0x41, 0x56, 0x45,
    ]) {
    Some("audio/wav")
  } else if bytes_match(bytes, [0x4f, 0x67, 0x67, 0x53]) {
    Some("audio/ogg")
  } else if bytes_match(bytes, [0x66, 0x4c, 0x61, 0x43]) {
    Some("audio/flac")
  } else if bytes_match(bytes, [0x40, 0x15, 0x00, 0x00]) {
    Some("audio/aac")
  } else if bytes_match(bytes, [0x1a, 0x45, 0xdf, 0xa3]) {
    Some("audio/webm")
  } else if include_mp4 &&
    bytes_match(bytes, [0x00, 0x00, 0x00, -1, 0x66, 0x74, 0x79, 0x70]) {
    Some("audio/mp4")
  } else {
    None
  }
}

///|
fn detect_video_media_type(bytes : BytesView) -> String? {
  if bytes_match(bytes, [0x00, 0x00, 0x00, -1, 0x66, 0x74, 0x79, 0x70]) {
    Some("video/mp4")
  } else if bytes_match(bytes, [0x1a, 0x45, 0xdf, 0xa3]) {
    Some("video/webm")
  } else if bytes_match(bytes, [
      0x00, 0x00, 0x00, 0x14, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74,
    ]) {
    Some("video/quicktime")
  } else if bytes_match(bytes, [0x52, 0x49, 0x46, 0x46]) {
    Some("video/x-msvideo")
  } else {
    None
  }
}

///|
/// Detect a media type from a bounded Base64 prefix. With no top-level hint,
/// MP4 containers resolve to video, matching AI SDK provider-utils.
pub fn detect_media_type(data : String, top_level_type? : String) -> String? {
  let initial = decoded_signature_prefix(data, 18)
  let bytes = match id3_tag_length(initial) {
    Some(offset) => {
      let scan = decoded_signature_prefix(data, 128 * 1024 + 18)
      if scan.length() > offset {
        scan[offset:]
      } else {
        scan
      }
    }
    None => initial
  }
  match top_level_type {
    Some("image") => detect_image_media_type(bytes)
    Some("application") => detect_application_media_type(bytes)
    Some("audio") => detect_audio_media_type(bytes, true)
    Some("video") => detect_video_media_type(bytes)
    Some(_) => None
    None =>
      match detect_image_media_type(bytes) {
        Some(value) => Some(value)
        None =>
          match detect_application_media_type(bytes) {
            Some(value) => Some(value)
            None =>
              match detect_audio_media_type(bytes, false) {
                Some(value) => Some(value)
                None => detect_video_media_type(bytes)
              }
          }
      }
  }
}

///|
/// Resolve a concrete media type for inline Base64 data.
pub fn resolve_full_media_type(
  media_type : String,
  data : String,
) -> String raise {
  if is_full_media_type(media_type) {
    return media_type
  }
  let top_level_type = get_top_level_media_type(media_type)
  match detect_media_type(data, top_level_type~) {
    Some(value) => value
    None =>
      fail(
        "file of media type '\{media_type}' must specify subtype because it could not be auto-detected",
      )
  }
}

///|
/// Decode Base64-backed text content as UTF-8.
pub fn decode_base64_text(data : String) -> String raise {
  let bytes = @base64.decode(data) catch {
    _ => fail("invalid Base64 text content")
  }
  @utf8.decode_lossy(bytes)
}
