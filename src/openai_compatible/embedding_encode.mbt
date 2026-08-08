///|
fn encode_embedding_request_data(
  model_id : String,
  values : Array[String],
  provider_options : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = Map([
    ("model", Json::string(model_id)),
    ("input", Json::array([ for value in values => Json::string(value) ])),
    ("encoding_format", Json::string("float")),
  ])
  for entry in provider_options.iter2() {
    let (key, value) = entry
    fields[key] = value
  }
  Json::object(fields)
}
