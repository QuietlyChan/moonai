///|
/// Severity used by Harness V1 diagnostics.
#derive(Debug, Eq)
pub(all) enum HarnessV1DebugLevel {
  HarnessDebugError
  HarnessDebugWarn
  HarnessDebugInfo
  HarnessDebugDebug
  HarnessDebugTrace
}

///|
/// Return the wire spelling of a diagnostic level.
pub fn HarnessV1DebugLevel::to_string(self : HarnessV1DebugLevel) -> String {
  match self {
    HarnessDebugError => "error"
    HarnessDebugWarn => "warn"
    HarnessDebugInfo => "info"
    HarnessDebugDebug => "debug"
    HarnessDebugTrace => "trace"
  }
}

///|
/// Decode a diagnostic level.
pub fn HarnessV1DebugLevel::from_string(
  value : String,
) -> HarnessV1DebugLevel raise HarnessError {
  match value {
    "error" => HarnessDebugError
    "warn" => HarnessDebugWarn
    "info" => HarnessDebugInfo
    "debug" => HarnessDebugDebug
    "trace" => HarnessDebugTrace
    _ => raise harness_error("Invalid harness debug level: " + value)
  }
}

///|
/// Per-session diagnostics configuration supplied to an adapter.
#derive(Debug, Eq)
pub(all) struct HarnessV1DebugConfig {
  enabled : Bool
  level : HarnessV1DebugLevel?
  subsystems : Array[String]
}

///|
/// One normalized adapter diagnostic.
#derive(Debug, Eq)
pub(all) struct HarnessV1Diagnostic {
  level : HarnessV1DebugLevel
  message : String
  subsystem : String
  kind : String
  source : String?
  stream : String?
  attrs : Json?
  error : Json?
  session_id : String?
  timestamp : UInt64
}

///|
/// Callback used by adapters to report diagnostics to the host.
pub type HarnessV1DiagnosticReporter = (HarnessV1Diagnostic) -> Unit

///|
/// Diagnostics wiring supplied to `HarnessV1::do_start`.
pub(all) struct HarnessV1Observability {
  debug : HarnessV1DebugConfig
  report : HarnessV1DiagnosticReporter
}
