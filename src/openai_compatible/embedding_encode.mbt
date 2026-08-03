///|
/// Encode a batch of text values as an OpenAI embeddings request.
pub fn encode_embedding_request(
  model_id : String,
  values : Array[String],
  options : @moonai.EmbeddingOptions,
) -> Json {
  let fields : Map[String, Json] = Map(
    [
      ("model", Json::string(model_id)),
      ("input", Json::array([ for value in values => Json::string(value) ])),
      ("encoding_format", Json::string("float")),
      ..if options.dimensions is Some(value) {
        [("dimensions", Json::number(value.to_double()))]
      },
      ..if options.user is Some(value) {
        [("user", Json::string(value))]
      },
    ],
  )
  for entry in options.provider_options.iter2() {
    let (key, value) = entry
    fields[key] = value
  }
  Json::object(fields)
}
