///|
/// Convert a `text/*` data URL to a text string, decoding the payload as
/// UTF-8. Mirrors upstream `getTextFromDataUrl`; malformed or undecodable
/// input raises `InvalidArgumentError` instead of a generic failure.
pub fn get_text_from_data_url(
  data_url : String,
) -> String raise InvalidArgumentError {
  let segments = data_url.split(",").to_array()
  let header = if segments.length() > 0 { segments[0].to_owned() } else { "" }
  let media_type = match header.split(";").to_array().get(0) {
    Some(prefix) => prefix.to_owned().split(":").to_array().get(1)
    None => None
  }
  if media_type is None || segments.length() < 2 {
    raise invalid_argument(
      parameter="dataUrl",
      value=Json::string(data_url),
      message="Invalid data URL format",
    )
  }
  @utf8.decode(@base64.decode(segments[1].to_owned())) catch {
    _ =>
      raise invalid_argument(
        parameter="dataUrl",
        value=Json::string(data_url),
        message="Error decoding data URL",
      )
  }
}

///|
/// AI SDK-style camel-case spelling for `get_text_from_data_url`.
pub fn getTextFromDataUrl(
  data_url : String,
) -> String raise InvalidArgumentError {
  get_text_from_data_url(data_url)
}
