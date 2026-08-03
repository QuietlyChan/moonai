///|
/// Copy headers so provider factories and models do not share mutable maps.
pub fn copy_headers(headers : Map[String, String]) -> Map[String, String] {
  let result : Map[String, String] = Map([])
  for entry in headers.iter2() {
    let (key, value) = entry
    result[key] = value
  }
  result
}
