///|
/// Spend-report aggregation dimension.
pub(all) enum GatewaySpendGroupBy {
  SpendDay
  SpendUser
  SpendModel
  SpendTag
  SpendProvider
  SpendCredentialType
} derive(Debug, Eq)

///|
fn gateway_spend_group_by_name(group_by~ : GatewaySpendGroupBy) -> String {
  match group_by {
    SpendDay => "day"
    SpendUser => "user"
    SpendModel => "model"
    SpendTag => "tag"
    SpendProvider => "provider"
    SpendCredentialType => "credential_type"
  }
}

///|
/// Parameters for the spend-report query. Dates are inclusive YYYY-MM-DD.
pub(all) struct GatewaySpendReportParams {
  start_date : String
  end_date : String
  group_by : GatewaySpendGroupBy?
  date_part_hour : Bool?
  user_id : String?
  model : String?
  provider : String?
  credential_type : String?
  tags : Array[String]?
} derive(Debug)

///|
/// One spend-report row. Only the fields relevant to the chosen group_by
/// dimension are present.
pub(all) struct GatewaySpendReportRow {
  day : String?
  hour : String?
  user : String?
  model : String?
  tag : String?
  provider_name : String?
  credential_type : String?
  total_cost : Double
  market_cost : Double?
  input_tokens : Int?
  output_tokens : Int?
  cached_input_tokens : Int?
  cache_creation_input_tokens : Int?
  reasoning_tokens : Int?
  request_count : Int?
} derive(Debug)

///|
fn gateway_spend_origin(base_url~ : String) -> String? {
  // Origin = scheme://host (strip scheme, then any path suffix).
  let after_scheme = match base_url.find("://") {
    Some(index) => base_url[index + 3:].to_owned()
    None => return None
  }
  // Origin = scheme://<host up to the first path slash>.
  let scheme_length = base_url.length() - after_scheme.length()
  match after_scheme.find("/") {
    Some(index) => Some(base_url[:scheme_length + index].to_owned())
    None => Some(base_url)
  }
}

///|
/// Build the /v1/report query string from the parameters.
fn gateway_spend_query(params~ : GatewaySpendReportParams) -> String {
  let pairs : Array[String] = []
  pairs.push("start_date=\{params.start_date}")
  pairs.push("end_date=\{params.end_date}")
  match params.group_by {
    Some(group_by) => {
      pairs.push("group_by=\{gateway_spend_group_by_name(group_by~)}")
      if group_by is SpendDay && params.date_part_hour is Some(true) {
        pairs.push("date_part=hour")
      }
    }
    None => ()
  }
  if params.user_id is Some(value) {
    pairs.push("user_id=\{value}")
  }
  if params.model is Some(value) {
    pairs.push("model=\{value}")
  }
  if params.provider is Some(value) {
    pairs.push("provider=\{value}")
  }
  if params.credential_type is Some(value) {
    pairs.push("credential_type=\{value}")
  }
  if params.tags is Some(tags) && tags.length() > 0 {
    let joined = StringBuilder()
    for i, tag in tags {
      if i > 0 {
        joined.write_string(",")
      }
      joined.write_string(tag)
    }
    pairs.push("tags=\{joined.to_string()}")
  }
  let builder = StringBuilder()
  for i, pair in pairs {
    if i > 0 {
      builder.write_string("&")
    }
    builder.write_string(pair)
  }
  builder.to_string()
}

///|
fn gateway_spend_row_string_field(value : Json, key~ : String) -> String? {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(String(text)) => Some(text)
        _ => None
      }
    _ => None
  }
}

///|
fn gateway_spend_row_int_field(value : Json, key~ : String) -> Int? {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(Number(count, ..)) => Some(count.to_int())
        _ => None
      }
    _ => None
  }
}

///|
fn gateway_spend_row_double_field(value : Json, key~ : String) -> Double? {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(Number(count, ..)) => Some(count)
        _ => None
      }
    _ => None
  }
}

///|
/// Decode one spend-report row from the gateway's snake_case payload.
fn decode_gateway_spend_row(row : Json) -> GatewaySpendReportRow raise {
  let text = key => gateway_spend_row_string_field(row, key~)
  let total_cost = gateway_spend_row_double_field(row, key="total_cost")
  guard total_cost is Some(total_cost_value) else {
    fail("gateway spend report row missing total_cost")
  }
  {
    day: text("day"),
    hour: text("hour"),
    user: text("user"),
    model: text("model"),
    tag: text("tag"),
    provider_name: text("provider"),
    credential_type: text("credential_type"),
    total_cost: total_cost_value,
    market_cost: gateway_spend_row_double_field(row, key="market_cost"),
    input_tokens: gateway_spend_row_int_field(row, key="input_tokens"),
    output_tokens: gateway_spend_row_int_field(row, key="output_tokens"),
    cached_input_tokens: gateway_spend_row_int_field(
      row,
      key="cached_input_tokens",
    ),
    cache_creation_input_tokens: gateway_spend_row_int_field(
      row,
      key="cache_creation_input_tokens",
    ),
    reasoning_tokens: gateway_spend_row_int_field(row, key="reasoning_tokens"),
    request_count: gateway_spend_row_int_field(row, key="request_count"),
  }
}

///|
/// The AI Gateway spend report client: GET {origin}/v1/report with query
/// parameters; the gateway origin is derived from the base URL.
pub struct GatewaySpendReport {
  priv api_key : String
  priv base_url : String
  priv headers : Map[String, String]
  priv idle_timeout_ms : Int
  priv http_transport : &@provider_utils.HttpTransport
}

///|
/// Create the spend-report client sharing the gateway credentials.
pub fn GatewaySpendReport::new(
  api_key~ : String,
  base_url~ : String,
  headers~ : Map[String, String],
  idle_timeout_ms~ : Int,
  http_transport~ : &@provider_utils.HttpTransport,
) -> GatewaySpendReport {
  { api_key, base_url, headers, idle_timeout_ms, http_transport, }
}

///|
/// Build the request headers for the report query.
fn GatewaySpendReport::report_headers(
  self : GatewaySpendReport,
  extra~ : Map[String, String],
) -> Map[String, String] raise @provider.LoadAPIKeyError {
  let api_key = @provider_utils.load_api_key(
    self.api_key,
    environment_variable_name="AI_GATEWAY_API_KEY",
    description="AI Gateway",
  )
  @provider_utils.with_user_agent_suffix(
    @provider_utils.merge_headers(
      @provider_utils.merge_headers(
        Map([("Authorization", "Bearer \{api_key}")]),
        self.headers,
      ),
      extra,
    ),
    ["ai-sdk/gateway/\{VERSION}"],
  )
}

///|
/// Fetch the spend report.
pub async fn GatewaySpendReport::get_spend_report(
  self : GatewaySpendReport,
  params~ : GatewaySpendReportParams,
) -> Array[GatewaySpendReportRow] {
  let origin = match gateway_spend_origin(base_url=self.base_url) {
    Some(origin) => origin
    None => fail("gateway base URL is not absolute")
  }
  let query = gateway_spend_query(params~)
  let response = @provider_utils.get_json(
    provider_name="gateway",
    url="\{origin}/v1/report?\{query}",
    headers=self.report_headers(extra=Map([])),
    timeout_ms=self.idle_timeout_ms,
    error_to_message=gateway_error_to_message,
    transport=self.http_transport,
  )
  let rows : Array[GatewaySpendReportRow] = []
  match response.value {
    { "results": Array(items), .. } =>
      for item in items {
        rows.push(decode_gateway_spend_row(item))
      }
    _ => ()
  }
  rows
}
