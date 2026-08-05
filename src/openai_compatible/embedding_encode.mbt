///|
/// Encode a batch of text values as an OpenAI embeddings request.
pub fn encode_embedding_request(
  model_id : String,
  values : Array[String],
  options : @provider.EmbeddingOptions,
  provider_name? : String = "",
) -> Json {
  let provider_options = resolve_compatible_options(
      options.provider_options,
      provider_name,
      embedding_reserved_fields(),
    ).values
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
  for entry in provider_options.iter2() {
    let (key, value) = entry
    fields[key] = value
  }
  Json::object(fields)
}
