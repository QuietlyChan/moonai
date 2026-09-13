///|
/// xAI Agent Tools: provider-executed tools advertised as `V4ProviderTool`
/// entries (id `xai.web_search`, `xai.x_search`, `xai.code_execution`).
/// The chat encoder maps them onto the xAI tools array wire entries.

///|
/// Construct the `xai.web_search` Agent Tool.
pub fn xai_web_search_tool(
  allowed_domains? : Array[String],
  excluded_domains? : Array[String],
  enable_image_search? : Bool,
  enable_image_understanding? : Bool,
) -> @provider.LanguageModelV4Tool {
  let args : Map[String, Json] = Map([])
  if allowed_domains is Some(values) {
    args["allowed_domains"] = Json::array(
      [
        for value in values => Json::string(value)
      ],
    )
  }
  if excluded_domains is Some(values) {
    args["excluded_domains"] = Json::array(
      [
        for value in values => Json::string(value)
      ],
    )
  }
  if enable_image_search is Some(value) {
    args["enable_image_search"] = Json::boolean(value)
  }
  if enable_image_understanding is Some(value) {
    args["enable_image_understanding"] = Json::boolean(value)
  }
  @provider.V4ProviderTool({
    id: "xai.web_search",
    name: "web_search",
    args: Json::object(args),
  })
}

///|
/// Construct the `xai.x_search` Agent Tool.
pub fn xai_x_search_tool(
  allowed_x_handles? : Array[String],
  excluded_x_handles? : Array[String],
  from_date? : String,
  to_date? : String,
  enable_image_understanding? : Bool,
  enable_video_understanding? : Bool,
) -> @provider.LanguageModelV4Tool {
  let args : Map[String, Json] = Map([])
  if allowed_x_handles is Some(values) {
    args["allowed_x_handles"] = Json::array(
      [
        for value in values => Json::string(value)
      ],
    )
  }
  if excluded_x_handles is Some(values) {
    args["excluded_x_handles"] = Json::array(
      [
        for value in values => Json::string(value)
      ],
    )
  }
  if from_date is Some(value) {
    args["from_date"] = Json::string(value)
  }
  if to_date is Some(value) {
    args["to_date"] = Json::string(value)
  }
  if enable_image_understanding is Some(value) {
    args["enable_image_understanding"] = Json::boolean(value)
  }
  if enable_video_understanding is Some(value) {
    args["enable_video_understanding"] = Json::boolean(value)
  }
  @provider.V4ProviderTool({
    id: "xai.x_search",
    name: "x_search",
    args: Json::object(args),
  })
}

///|
/// Construct the `xai.code_execution` Agent Tool (server-side interpreter).
pub fn xai_code_execution_tool() -> @provider.LanguageModelV4Tool {
  @provider.V4ProviderTool({
    id: "xai.code_execution",
    name: "code_execution",
    args: Json::object(Map([])),
  })
}

///|
/// Encode a provider tool entry for the xAI tools array (Agent Tools API).
pub fn xai_encode_provider_tool(
  value : @provider.LanguageModelV4ProviderTool,
) -> Json? {
  let fields : Map[String, Json] = Map([])
  match value.id {
    "xai.web_search" => fields["type"] = Json::string("web_search")
    "xai.x_search" => fields["type"] = Json::string("x_search")
    "xai.code_execution" => fields["type"] = Json::string("code_interpreter")
    _ => return None
  }
  if value.args is Object(args) {
    for entry in args.iter2() {
      fields[entry.0] = entry.1
    }
  }
  Some(Json::object(fields))
}
