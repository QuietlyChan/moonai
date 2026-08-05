///|
/// Comparison operator used by OpenAI file-search metadata filters.
pub(all) enum OpenAIFileSearchComparisonOperator {
  FileSearchEq
  FileSearchNe
  FileSearchGt
  FileSearchGte
  FileSearchLt
  FileSearchLte
  FileSearchIn
  FileSearchNin
} derive(Debug, Eq)

///|
fn OpenAIFileSearchComparisonOperator::wire_name(
  self : OpenAIFileSearchComparisonOperator,
) -> String {
  match self {
    FileSearchEq => "eq"
    FileSearchNe => "ne"
    FileSearchGt => "gt"
    FileSearchGte => "gte"
    FileSearchLt => "lt"
    FileSearchLte => "lte"
    FileSearchIn => "in"
    FileSearchNin => "nin"
  }
}

///|
/// Recursive OpenAI file-search metadata filter.
pub(all) enum OpenAIFileSearchFilter {
  FileSearchComparison(
    key~ : String,
    operator~ : OpenAIFileSearchComparisonOperator,
    value~ : Json
  )
  FileSearchAnd(filters~ : Array[OpenAIFileSearchFilter])
  FileSearchOr(filters~ : Array[OpenAIFileSearchFilter])
} derive(Debug, Eq)

///|
fn openai_file_search_filter_value_is_valid(value : Json) -> Bool {
  match value {
    String(_) | Number(_) | True | False => true
    Array(values) => {
      for item in values {
        guard item is String(_) else { return false }
      }
      true
    }
    _ => false
  }
}

///|
/// Construct a file-search comparison filter.
pub fn OpenAIFileSearchFilter::comparison(
  key~ : String,
  operator~ : OpenAIFileSearchComparisonOperator,
  value~ : Json,
) -> OpenAIFileSearchFilter raise {
  guard !key.trim().is_empty() else {
    fail("OpenAI file-search filter key must not be empty")
  }
  guard openai_file_search_filter_value_is_valid(value) else {
    fail(
      "OpenAI file-search filter value must be a string, number, boolean, or string array",
    )
  }
  FileSearchComparison(key~, operator~, value~)
}

///|
/// Combine file-search filters with logical AND.
pub fn OpenAIFileSearchFilter::all(
  filters : Array[OpenAIFileSearchFilter],
) -> OpenAIFileSearchFilter {
  FileSearchAnd(filters~)
}

///|
/// Combine file-search filters with logical OR.
pub fn OpenAIFileSearchFilter::any(
  filters : Array[OpenAIFileSearchFilter],
) -> OpenAIFileSearchFilter {
  FileSearchOr(filters~)
}

///|
fn OpenAIFileSearchFilter::to_json(self : OpenAIFileSearchFilter) -> Json {
  match self {
    FileSearchComparison(key~, operator~, value~) =>
      { "key": key, "type": operator.wire_name(), "value": value }
    FileSearchAnd(filters~) =>
      {
        "type": "and",
        "filters": Json::array([ for filter in filters => filter.to_json() ]),
      }
    FileSearchOr(filters~) =>
      {
        "type": "or",
        "filters": Json::array([ for filter in filters => filter.to_json() ]),
      }
  }
}

///|
/// Ranking configuration for OpenAI file search.
pub(all) struct OpenAIFileSearchRanking {
  ranker : String?
  score_threshold : Double?
} derive(Debug, Eq)

///|
/// Construct and validate OpenAI file-search ranking options.
pub fn OpenAIFileSearchRanking::new(
  ranker? : String,
  score_threshold? : Double,
) -> OpenAIFileSearchRanking raise {
  guard score_threshold is None ||
    (score_threshold.unwrap() >= 0.0 && score_threshold.unwrap() <= 1.0) else {
    fail("OpenAI file-search score_threshold must be between 0 and 1")
  }
  guard ranker is None || !ranker.unwrap().trim().is_empty() else {
    fail("OpenAI file-search ranker must not be empty")
  }
  { ranker, score_threshold }
}

///|
/// Typed arguments for the OpenAI file-search provider tool.
pub(all) struct OpenAIFileSearchOptions {
  vector_store_ids : Array[String]
  max_num_results : Int?
  ranking : OpenAIFileSearchRanking?
  filters : OpenAIFileSearchFilter?
} derive(Debug, Eq)

///|
/// Construct and validate typed OpenAI file-search arguments.
pub fn OpenAIFileSearchOptions::new(
  vector_store_ids~ : Array[String],
  max_num_results? : Int,
  ranking? : OpenAIFileSearchRanking,
  filters? : OpenAIFileSearchFilter,
) -> OpenAIFileSearchOptions raise {
  guard vector_store_ids.length() > 0 else {
    fail("OpenAI file search requires at least one vector store ID")
  }
  for vector_store_id in vector_store_ids {
    guard !vector_store_id.trim().is_empty() else {
      fail("OpenAI file-search vector store IDs must not be empty")
    }
  }
  guard max_num_results is None || max_num_results.unwrap() > 0 else {
    fail("OpenAI file-search max_num_results must be positive")
  }
  { vector_store_ids, max_num_results, ranking, filters }
}

///|
/// Encode file-search arguments using the camel-case tool-factory schema.
pub fn OpenAIFileSearchOptions::to_args_json(
  self : OpenAIFileSearchOptions,
) -> Json {
  Json::object(
    Map(
      [
        (
          "vectorStoreIds",
          Json::array(
            [
              for value in self.vector_store_ids => Json::string(value)
            ],
          ),
        ),
        ..if self.max_num_results is Some(value) {
          [("maxNumResults", Json::number(value.to_double()))]
        },
        ..if self.ranking is Some(value) {
          [
            (
              "ranking",
              Json::object(
                Map(
                  [
                    ..if value.ranker is Some(ranker) {
                      [("ranker", Json::string(ranker))]
                    },
                    ..if value.score_threshold is Some(threshold) {
                      [("scoreThreshold", Json::number(threshold))]
                    },
                  ],
                ),
              ),
            ),
          ]
        },
        ..if self.filters is Some(value) {
          [("filters", value.to_json())]
        },
      ],
    ),
  )
}

///|
/// OpenAI web-search context size.
pub(all) enum OpenAIWebSearchContextSize {
  WebSearchLow
  WebSearchMedium
  WebSearchHigh
} derive(Debug, Eq)

///|
fn OpenAIWebSearchContextSize::wire_name(
  self : OpenAIWebSearchContextSize,
) -> String {
  match self {
    WebSearchLow => "low"
    WebSearchMedium => "medium"
    WebSearchHigh => "high"
  }
}

///|
/// Approximate user location supplied to OpenAI web search.
pub(all) struct OpenAIWebSearchUserLocation {
  country : String?
  city : String?
  region : String?
  timezone : String?
} derive(Debug, Eq)

///|
/// Construct an approximate location for OpenAI web search.
pub fn OpenAIWebSearchUserLocation::new(
  country? : String,
  city? : String,
  region? : String,
  timezone? : String,
) -> OpenAIWebSearchUserLocation {
  { country, city, region, timezone }
}

///|
fn OpenAIWebSearchUserLocation::to_json(
  self : OpenAIWebSearchUserLocation,
) -> Json {
  Json::object(
    Map(
      [
        ("type", Json::string("approximate")),
        ..if self.country is Some(value) {
          [("country", Json::string(value))]
        },
        ..if self.city is Some(value) {
          [("city", Json::string(value))]
        },
        ..if self.region is Some(value) {
          [("region", Json::string(value))]
        },
        ..if self.timezone is Some(value) {
          [("timezone", Json::string(value))]
        },
      ],
    ),
  )
}

///|
/// Domain filters for OpenAI web search.
pub(all) struct OpenAIWebSearchFilters {
  allowed_domains : Array[String]?
  blocked_domains : Array[String]?
} derive(Debug, Eq)

///|
/// Construct and validate OpenAI web-search domain filters.
pub fn OpenAIWebSearchFilters::new(
  allowed_domains? : Array[String],
  blocked_domains? : Array[String],
) -> OpenAIWebSearchFilters raise {
  guard allowed_domains is None || allowed_domains.unwrap().length() <= 100 else {
    fail("OpenAI web-search allowed_domains supports at most 100 domains")
  }
  guard blocked_domains is None || blocked_domains.unwrap().length() <= 100 else {
    fail("OpenAI web-search blocked_domains supports at most 100 domains")
  }
  if allowed_domains is Some(values) {
    for domain in values {
      guard !domain.trim().is_empty() else {
        fail("OpenAI web-search allowed domains must not be empty")
      }
    }
  }
  if blocked_domains is Some(values) {
    for domain in values {
      guard !domain.trim().is_empty() else {
        fail("OpenAI web-search blocked domains must not be empty")
      }
    }
  }
  { allowed_domains, blocked_domains }
}

///|
fn openai_optional_string_array(value : Array[String]?) -> Json? {
  match value {
    Some(values) =>
      Some(Json::array([ for item in values => Json::string(item) ]))
    None => None
  }
}

///|
fn OpenAIWebSearchFilters::to_json(self : OpenAIWebSearchFilters) -> Json {
  Json::object(
    Map(
      [
        ..if openai_optional_string_array(self.allowed_domains) is Some(value) {
          [("allowedDomains", value)]
        },
        ..if openai_optional_string_array(self.blocked_domains) is Some(value) {
          [("blockedDomains", value)]
        },
      ],
    ),
  )
}

///|
/// Typed arguments for the current OpenAI web-search tool.
pub(all) struct OpenAIWebSearchOptions {
  external_web_access : Bool?
  filters : OpenAIWebSearchFilters?
  search_context_size : OpenAIWebSearchContextSize?
  user_location : OpenAIWebSearchUserLocation?
} derive(Debug, Eq)

///|
/// Construct typed arguments for the current OpenAI web-search tool.
pub fn OpenAIWebSearchOptions::new(
  external_web_access? : Bool,
  filters? : OpenAIWebSearchFilters,
  search_context_size? : OpenAIWebSearchContextSize,
  user_location? : OpenAIWebSearchUserLocation,
) -> OpenAIWebSearchOptions {
  { external_web_access, filters, search_context_size, user_location }
}

///|
/// Encode web-search arguments using the camel-case tool-factory schema.
pub fn OpenAIWebSearchOptions::to_args_json(
  self : OpenAIWebSearchOptions,
) -> Json {
  Json::object(
    Map(
      [
        ..if self.external_web_access is Some(value) {
          [("externalWebAccess", Json::boolean(value))]
        },
        ..if self.filters is Some(value) {
          [("filters", value.to_json())]
        },
        ..if self.search_context_size is Some(value) {
          [("searchContextSize", Json::string(value.wire_name()))]
        },
        ..if self.user_location is Some(value) {
          [("userLocation", value.to_json())]
        },
      ],
    ),
  )
}

///|
/// Typed arguments for the preview OpenAI web-search tool.
pub(all) struct OpenAIWebSearchPreviewOptions {
  search_context_size : OpenAIWebSearchContextSize?
  user_location : OpenAIWebSearchUserLocation?
} derive(Debug, Eq)

///|
/// Construct typed arguments for the preview OpenAI web-search tool.
pub fn OpenAIWebSearchPreviewOptions::new(
  search_context_size? : OpenAIWebSearchContextSize,
  user_location? : OpenAIWebSearchUserLocation,
) -> OpenAIWebSearchPreviewOptions {
  { search_context_size, user_location }
}

///|
/// Encode preview web-search arguments using the tool-factory schema.
pub fn OpenAIWebSearchPreviewOptions::to_args_json(
  self : OpenAIWebSearchPreviewOptions,
) -> Json {
  Json::object(
    Map(
      [
        ..if self.search_context_size is Some(value) {
          [("searchContextSize", Json::string(value.wire_name()))]
        },
        ..if self.user_location is Some(value) {
          [("userLocation", value.to_json())]
        },
      ],
    ),
  )
}

///|
/// Background handling for OpenAI image generation.
pub(all) enum OpenAIImageGenerationBackground {
  ImageBackgroundAuto
  ImageBackgroundOpaque
  ImageBackgroundTransparent
} derive(Debug, Eq)

///|
fn OpenAIImageGenerationBackground::wire_name(
  self : OpenAIImageGenerationBackground,
) -> String {
  match self {
    ImageBackgroundAuto => "auto"
    ImageBackgroundOpaque => "opaque"
    ImageBackgroundTransparent => "transparent"
  }
}

///|
/// Input-image fidelity for OpenAI image generation.
pub(all) enum OpenAIImageGenerationInputFidelity {
  ImageFidelityLow
  ImageFidelityHigh
} derive(Debug, Eq)

///|
fn OpenAIImageGenerationInputFidelity::wire_name(
  self : OpenAIImageGenerationInputFidelity,
) -> String {
  match self {
    ImageFidelityLow => "low"
    ImageFidelityHigh => "high"
  }
}

///|
/// Moderation mode for OpenAI image generation.
pub(all) enum OpenAIImageGenerationModeration {
  ImageModerationAuto
} derive(Debug, Eq)

///|
fn OpenAIImageGenerationModeration::wire_name(
  self : OpenAIImageGenerationModeration,
) -> String {
  match self {
    ImageModerationAuto => "auto"
  }
}

///|
/// Output encoding for OpenAI image generation.
pub(all) enum OpenAIImageGenerationOutputFormat {
  ImageFormatPng
  ImageFormatJpeg
  ImageFormatWebp
} derive(Debug, Eq)

///|
fn OpenAIImageGenerationOutputFormat::wire_name(
  self : OpenAIImageGenerationOutputFormat,
) -> String {
  match self {
    ImageFormatPng => "png"
    ImageFormatJpeg => "jpeg"
    ImageFormatWebp => "webp"
  }
}

///|
/// Quality level for OpenAI image generation.
pub(all) enum OpenAIImageGenerationQuality {
  ImageQualityAuto
  ImageQualityLow
  ImageQualityMedium
  ImageQualityHigh
} derive(Debug, Eq)

///|
fn OpenAIImageGenerationQuality::wire_name(
  self : OpenAIImageGenerationQuality,
) -> String {
  match self {
    ImageQualityAuto => "auto"
    ImageQualityLow => "low"
    ImageQualityMedium => "medium"
    ImageQualityHigh => "high"
  }
}

///|
/// Canvas size for OpenAI image generation.
pub(all) enum OpenAIImageGenerationSize {
  ImageSizeAuto
  ImageSize1024x1024
  ImageSize1024x1536
  ImageSize1536x1024
} derive(Debug, Eq)

///|
fn OpenAIImageGenerationSize::wire_name(
  self : OpenAIImageGenerationSize,
) -> String {
  match self {
    ImageSizeAuto => "auto"
    ImageSize1024x1024 => "1024x1024"
    ImageSize1024x1536 => "1024x1536"
    ImageSize1536x1024 => "1536x1024"
  }
}

///|
/// Optional file or data-URL mask used for image inpainting.
pub(all) struct OpenAIImageGenerationMask {
  file_id : String?
  image_url : String?
} derive(Debug, Eq)

///|
/// Construct an OpenAI image-generation mask.
pub fn OpenAIImageGenerationMask::new(
  file_id? : String,
  image_url? : String,
) -> OpenAIImageGenerationMask {
  { file_id, image_url }
}

///|
fn OpenAIImageGenerationMask::to_json(self : OpenAIImageGenerationMask) -> Json {
  Json::object(
    Map(
      [
        ..if self.file_id is Some(value) {
          [("fileId", Json::string(value))]
        },
        ..if self.image_url is Some(value) {
          [("imageUrl", Json::string(value))]
        },
      ],
    ),
  )
}

///|
/// Typed arguments for the OpenAI image-generation provider tool.
pub(all) struct OpenAIImageGenerationOptions {
  background : OpenAIImageGenerationBackground?
  input_fidelity : OpenAIImageGenerationInputFidelity?
  input_image_mask : OpenAIImageGenerationMask?
  model : String?
  moderation : OpenAIImageGenerationModeration?
  output_compression : Int?
  output_format : OpenAIImageGenerationOutputFormat?
  partial_images : Int?
  quality : OpenAIImageGenerationQuality?
  size : OpenAIImageGenerationSize?
} derive(Debug, Eq)

///|
/// Construct and validate typed OpenAI image-generation arguments.
pub fn OpenAIImageGenerationOptions::new(
  background? : OpenAIImageGenerationBackground,
  input_fidelity? : OpenAIImageGenerationInputFidelity,
  input_image_mask? : OpenAIImageGenerationMask,
  model? : String,
  moderation? : OpenAIImageGenerationModeration,
  output_compression? : Int,
  output_format? : OpenAIImageGenerationOutputFormat,
  partial_images? : Int,
  quality? : OpenAIImageGenerationQuality,
  size? : OpenAIImageGenerationSize,
) -> OpenAIImageGenerationOptions raise {
  guard output_compression is None ||
    (output_compression.unwrap() >= 0 && output_compression.unwrap() <= 100) else {
    fail("OpenAI image-generation output_compression must be between 0 and 100")
  }
  guard partial_images is None ||
    (partial_images.unwrap() >= 0 && partial_images.unwrap() <= 3) else {
    fail("OpenAI image-generation partial_images must be between 0 and 3")
  }
  {
    background,
    input_fidelity,
    input_image_mask,
    model,
    moderation,
    output_compression,
    output_format,
    partial_images,
    quality,
    size,
  }
}

///|
/// Encode image-generation arguments using the tool-factory schema.
pub fn OpenAIImageGenerationOptions::to_args_json(
  self : OpenAIImageGenerationOptions,
) -> Json {
  Json::object(
    Map(
      [
        ..if self.background is Some(value) {
          [("background", Json::string(value.wire_name()))]
        },
        ..if self.input_fidelity is Some(value) {
          [("inputFidelity", Json::string(value.wire_name()))]
        },
        ..if self.input_image_mask is Some(value) {
          [("inputImageMask", value.to_json())]
        },
        ..if self.model is Some(value) {
          [("model", Json::string(value))]
        },
        ..if self.moderation is Some(value) {
          [("moderation", Json::string(value.wire_name()))]
        },
        ..if self.output_compression is Some(value) {
          [("outputCompression", Json::number(value.to_double()))]
        },
        ..if self.output_format is Some(value) {
          [("outputFormat", Json::string(value.wire_name()))]
        },
        ..if self.partial_images is Some(value) {
          [("partialImages", Json::number(value.to_double()))]
        },
        ..if self.quality is Some(value) {
          [("quality", Json::string(value.wire_name()))]
        },
        ..if self.size is Some(value) {
          [("size", Json::string(value.wire_name()))]
        },
      ],
    ),
  )
}

///|
/// OpenAI MCP tool allowlist configuration.
pub(all) enum OpenAIMCPAllowedTools {
  MCPAllowedNames(Array[String])
  MCPAllowedFilter(read_only~ : Bool?, tool_names~ : Array[String]?)
} derive(Debug, Eq)

///|
/// Restrict an MCP server to an explicit list of tool names.
pub fn OpenAIMCPAllowedTools::names(
  values : Array[String],
) -> OpenAIMCPAllowedTools {
  MCPAllowedNames(values)
}

///|
/// Restrict MCP tools by read-only status and optional names.
pub fn OpenAIMCPAllowedTools::filter(
  read_only? : Bool,
  tool_names? : Array[String],
) -> OpenAIMCPAllowedTools {
  MCPAllowedFilter(read_only~, tool_names~)
}

///|
fn OpenAIMCPAllowedTools::to_json(self : OpenAIMCPAllowedTools) -> Json {
  match self {
    MCPAllowedNames(values) =>
      Json::array([ for value in values => Json::string(value) ])
    MCPAllowedFilter(read_only~, tool_names~) =>
      Json::object(
        Map(
          [
            ..if read_only is Some(value) {
              [("readOnly", Json::boolean(value))]
            },
            ..if openai_optional_string_array(tool_names) is Some(value) {
              [("toolNames", value)]
            },
          ],
        ),
      )
  }
}

///|
/// OpenAI MCP approval policy.
pub(all) enum OpenAIMCPApprovalPolicy {
  MCPApprovalAlways
  MCPApprovalNever
  MCPApprovalNeverFor(tool_names~ : Array[String]?)
} derive(Debug, Eq)

///|
/// Require approval except for an optional list of MCP tool names.
pub fn OpenAIMCPApprovalPolicy::never_for(
  tool_names? : Array[String],
) -> OpenAIMCPApprovalPolicy {
  MCPApprovalNeverFor(tool_names~)
}

///|
fn OpenAIMCPApprovalPolicy::to_json(self : OpenAIMCPApprovalPolicy) -> Json {
  match self {
    MCPApprovalAlways => Json::string("always")
    MCPApprovalNever => Json::string("never")
    MCPApprovalNeverFor(tool_names~) =>
      {
        "never": Json::object(
          Map(
            [
              ..if openai_optional_string_array(tool_names) is Some(value) {
                [("toolNames", value)]
              },
            ],
          ),
        ),
      }
  }
}

///|
/// Typed arguments for the OpenAI MCP provider tool.
pub(all) struct OpenAIMCPOptions {
  server_label : String
  allowed_tools : OpenAIMCPAllowedTools?
  authorization : String?
  connector_id : String?
  headers : Map[String, String]?
  require_approval : OpenAIMCPApprovalPolicy?
  server_description : String?
  server_url : String?
} derive(Debug, Eq)

///|
/// Construct and validate typed OpenAI MCP arguments.
pub fn OpenAIMCPOptions::new(
  server_label~ : String,
  allowed_tools? : OpenAIMCPAllowedTools,
  authorization? : String,
  connector_id? : String,
  headers? : Map[String, String],
  require_approval? : OpenAIMCPApprovalPolicy,
  server_description? : String,
  server_url? : String,
) -> OpenAIMCPOptions raise {
  guard !server_label.trim().is_empty() else {
    fail("OpenAI MCP server_label must not be empty")
  }
  let has_server_url = match server_url {
    Some(value) => !value.trim().is_empty()
    None => false
  }
  let has_connector_id = match connector_id {
    Some(value) => !value.trim().is_empty()
    None => false
  }
  guard has_server_url || has_connector_id else {
    fail("OpenAI MCP requires server_url or connector_id")
  }
  {
    server_label,
    allowed_tools,
    authorization,
    connector_id,
    headers,
    require_approval,
    server_description,
    server_url,
  }
}

///|
/// Encode MCP arguments using the camel-case tool-factory schema.
pub fn OpenAIMCPOptions::to_args_json(self : OpenAIMCPOptions) -> Json {
  let header_json = match self.headers {
    Some(values) => {
      let fields : Map[String, Json] = Map([])
      for entry in values.iter2() {
        fields[entry.0] = Json::string(entry.1)
      }
      Some(Json::object(fields))
    }
    None => None
  }
  Json::object(
    Map(
      [
        ("serverLabel", Json::string(self.server_label)),
        ..if self.allowed_tools is Some(value) {
          [("allowedTools", value.to_json())]
        },
        ..if self.authorization is Some(value) {
          [("authorization", Json::string(value))]
        },
        ..if self.connector_id is Some(value) {
          [("connectorId", Json::string(value))]
        },
        ..if header_json is Some(value) {
          [("headers", value)]
        },
        ..if self.require_approval is Some(value) {
          [("requireApproval", value.to_json())]
        },
        ..if self.server_description is Some(value) {
          [("serverDescription", Json::string(value))]
        },
        ..if self.server_url is Some(value) {
          [("serverUrl", Json::string(value))]
        },
      ],
    ),
  )
}

///|
/// Grammar syntax supported by an OpenAI custom tool.
pub(all) enum OpenAICustomToolGrammarSyntax {
  CustomGrammarRegex
  CustomGrammarLark
} derive(Debug, Eq)

///|
/// Output format accepted from an OpenAI custom tool.
pub(all) enum OpenAICustomToolFormat {
  CustomTextFormat
  CustomGrammarFormat(
    syntax~ : OpenAICustomToolGrammarSyntax,
    definition~ : String
  )
} derive(Debug, Eq)

///|
fn OpenAICustomToolFormat::to_json(self : OpenAICustomToolFormat) -> Json {
  match self {
    CustomTextFormat => ({ "type": "text" } : Json)
    CustomGrammarFormat(syntax~, definition~) =>
      {
        "type": "grammar",
        "syntax": match syntax {
          CustomGrammarRegex => "regex"
          CustomGrammarLark => "lark"
        },
        "definition": definition,
      }
  }
}

///|
/// Typed arguments for an OpenAI custom provider tool.
pub(all) struct OpenAICustomToolOptions {
  description : String?
  format : OpenAICustomToolFormat?
} derive(Debug, Eq)

///|
/// Construct typed OpenAI custom-tool arguments.
pub fn OpenAICustomToolOptions::new(
  description? : String,
  format? : OpenAICustomToolFormat,
) -> OpenAICustomToolOptions {
  { description, format }
}

///|
/// Encode custom-tool arguments using the tool-factory schema.
pub fn OpenAICustomToolOptions::to_args_json(
  self : OpenAICustomToolOptions,
) -> Json {
  Json::object(
    Map(
      [
        ..if self.description is Some(value) {
          [("description", Json::string(value))]
        },
        ..if self.format is Some(value) {
          [("format", value.to_json())]
        },
      ],
    ),
  )
}

///|
/// Select whether OpenAI or the client executes tool search.
pub(all) enum OpenAIToolSearchExecution {
  ToolSearchServer
  ToolSearchClient
} derive(Debug, Eq)

///|
fn OpenAIToolSearchExecution::wire_name(
  self : OpenAIToolSearchExecution,
) -> String {
  match self {
    ToolSearchServer => "server"
    ToolSearchClient => "client"
  }
}

///|
/// Typed arguments for the OpenAI tool-search provider tool.
pub(all) struct OpenAIToolSearchOptions {
  execution : OpenAIToolSearchExecution?
  description : String?
  parameters : Json?
} derive(Debug, Eq)

///|
/// Construct and validate typed OpenAI tool-search arguments.
pub fn OpenAIToolSearchOptions::new(
  execution? : OpenAIToolSearchExecution,
  description? : String,
  parameters? : Json,
) -> OpenAIToolSearchOptions raise {
  guard parameters is None || parameters.unwrap() is Object(_) else {
    fail("OpenAI tool-search parameters must be a JSON object")
  }
  { execution, description, parameters }
}

///|
/// Encode tool-search arguments using the tool-factory schema.
pub fn OpenAIToolSearchOptions::to_args_json(
  self : OpenAIToolSearchOptions,
) -> Json {
  Json::object(
    Map(
      [
        ..if self.execution is Some(value) {
          [("execution", Json::string(value.wire_name()))]
        },
        ..if self.description is Some(value) {
          [("description", Json::string(value))]
        },
        ..if self.parameters is Some(value) {
          [("parameters", value)]
        },
      ],
    ),
  )
}
