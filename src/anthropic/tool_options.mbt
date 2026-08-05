///|
/// Caller that may invoke an Anthropic function tool.
pub(all) enum AnthropicToolAllowedCaller {
  AnthropicToolDirect
  AnthropicToolCodeExecution20250825
  AnthropicToolCodeExecution20260120
} derive(Debug, Eq)

///|
fn AnthropicToolAllowedCaller::wire_name(
  self : AnthropicToolAllowedCaller,
) -> String {
  match self {
    AnthropicToolDirect => "direct"
    AnthropicToolCodeExecution20250825 => "code_execution_20250825"
    AnthropicToolCodeExecution20260120 => "code_execution_20260120"
  }
}

///|
/// Anthropic-specific options for a function tool.
pub(all) struct AnthropicToolOptions {
  defer_loading : Bool?
  allowed_callers : Array[AnthropicToolAllowedCaller]
  eager_input_streaming : Bool?
} derive(Debug, Eq)

///|
/// Construct typed Anthropic function-tool options.
pub fn AnthropicToolOptions::new(
  defer_loading? : Bool,
  allowed_callers? : Array[AnthropicToolAllowedCaller] = [],
  eager_input_streaming? : Bool,
) -> AnthropicToolOptions {
  {
    defer_loading,
    allowed_callers: allowed_callers.copy(),
    eager_input_streaming,
  }
}

///|
/// Convert typed function-tool options to an Anthropic provider namespace.
pub fn AnthropicToolOptions::to_provider_options(
  self : AnthropicToolOptions,
  provider_name? : String = "anthropic",
) -> Map[String, Json] {
  let fields : Map[String, Json] = Map(
    [
      ..if self.defer_loading is Some(value) {
        [("deferLoading", Json::boolean(value))]
      },
      ..if self.allowed_callers.length() > 0 {
        [
          (
            "allowedCallers",
            Json::array(
              [
                for caller in self.allowed_callers => {
                  Json::string(caller.wire_name())
                }
              ],
            ),
          ),
        ]
      },
      ..if self.eager_input_streaming is Some(value) {
        [("eagerInputStreaming", Json::boolean(value))]
      },
    ],
  )
  Map([(provider_name, Json::object(fields))])
}
