///|
/// Format a warning into a human-readable string with clear AI SDK branding
/// (upstream `formatWarning`).
pub fn format_warning(
  warning~ : @provider.Warning,
  provider~ : String?,
  model~ : String?,
) -> String {
  let parts : Array[String] = []
  parts.push("AI SDK Warning: \{@debug.to_string(warning)}")
  if provider is Some(value) && value != "" {
    parts.push("\{value}")
  }
  if model is Some(value) && value != "" {
    parts.push("\{value}")
  }
  let builder = StringBuilder()
  for part in parts {
    builder.write_string(part)
    builder.write_string(" ")
  }
  builder.to_string().trim().to_owned()
}

///|
/// Options passed to a warning logger.
pub(all) struct LogWarningsOptions {
  warnings : Array[@provider.Warning]
  provider : String?
  model : String?
} derive(Debug)

///|
/// Log model-provider warnings through the default logger: warnings go to
/// the warning sink, the informational first-call banner goes to the info
/// sink (each emitted once per process, matching upstream
/// `AI_SDK_LOG_WARNINGS` semantics).
pub fn log_warnings(options~ : LogWarningsOptions) -> Unit {
  if options.warnings.length() == 0 {
    return
  }
  if !warning_banner_logged.val {
    warning_banner_logged.val = true
    println("AI SDK: 1 experimental warning in total is hidden.")
  }
  for warning in options.warnings {
    println(
      format_warning(warning~, provider=options.provider, model=options.model),
    )
  }
}

///|
/// Process-wide flag: the informational banner is emitted only once.
let warning_banner_logged : Ref[Bool] = Ref(false)
