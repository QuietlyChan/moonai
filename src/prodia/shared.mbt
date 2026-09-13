///|
fn prodia_error_to_message(json : Json) -> String? raise {
  // Adapt the pure built-in parser to the fallible transport hook contract.
  @provider.check_cancellation(None)
  match json {
    { "message": String(message), .. } => Some(message)
    { "error": String(message), .. } => Some(message)
    { "error": { "message": String(message), .. }, .. } => Some(message)
    _ => None
  }
}

///|
fn prodia_request_headers(
  api_key~ : String,
  headers~ : Map[String, String],
  extra~ : Map[String, String],
  content_type~ : String,
  accept~ : String,
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    api_key,
    environment_variable_name="PRODIA_TOKEN",
    description="Prodia",
  )
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([
          ("Authorization", "Bearer \{api_key}"),
          ("Content-Type", content_type),
          ("Accept", accept),
        ]),
        headers,
      ),
      extra,
    ),
    ["ai-sdk/prodia/\{VERSION}"],
  )
}

///|
/// Flatten the Prodia job result (id/state/metrics/price) into provider
/// metadata under the `prodia` namespace.
fn prodia_job_metadata(job : Json) -> Map[String, Json] {
  let metadata : Map[String, Json] = Map([])
  if job is Object(fields) {
    if fields.get("id") is Some(value) {
      metadata["id"] = value
    }
    match fields.get("state") {
      Some({ "current": String(current), .. }) =>
        metadata["state"] = Json::string(current)
      _ => ()
    }
    match fields.get("metrics") {
      Some(Object(metrics)) => metadata["metrics"] = Json::object(metrics)
      _ => ()
    }
    match fields.get("price") {
      Some(Object(price)) => metadata["price"] = Json::object(price)
      _ => ()
    }
  }
  Map([("prodia", Json::object(metadata))])
}

///|
/// Decode the named `job` part into the job-result JSON.
fn decode_prodia_job_part(
  parts : Array[@provider_utils.MultipartResponsePart],
) -> Json raise {
  let job = @provider_utils.multipart_response_part_by_name(parts, name="job")
  guard job is Some(part) else {
    fail("prodia multipart response missing job part")
  }
  let text = @utf8.decode(part.body)
  @json.parse(text) catch {
    _ => fail("prodia job part is not valid JSON")
  }
}
