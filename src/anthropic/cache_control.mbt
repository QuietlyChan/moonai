///|
const ANTHROPIC_MAX_CACHE_BREAKPOINTS : Int = 4

///|
/// Track Anthropic cache breakpoints across one request. The same validator is
/// shared by prompt conversion and tool preparation so the provider's limit is
/// enforced in wire order.
priv struct AnthropicCacheControlValidator {
  mut breakpoint_count : Int
  warnings : Array[@provider.Warning]
}

///|
fn AnthropicCacheControlValidator::new() -> AnthropicCacheControlValidator {
  { breakpoint_count: 0, warnings: [] }
}

///|
fn AnthropicCacheControlValidator::get_cache_control(
  self : AnthropicCacheControlValidator,
  options : Map[String, Json],
  provider_name : String,
  context_type : String,
  can_cache : Bool,
) -> Json? {
  match anthropic_cache_control(options, provider_name) {
    None => None
    Some(value) => {
      if !can_cache {
        self.warnings.push(
          @provider.Warning::Unsupported(
            feature="cache_control on non-cacheable context",
            details="cache_control cannot be set on \{context_type}. It will be ignored.",
          ),
        )
        return None
      }
      self.breakpoint_count = self.breakpoint_count + 1
      if self.breakpoint_count > ANTHROPIC_MAX_CACHE_BREAKPOINTS {
        self.warnings.push(
          @provider.Warning::Unsupported(
            feature="cacheControl breakpoint limit",
            details="Maximum \{ANTHROPIC_MAX_CACHE_BREAKPOINTS} cache breakpoints exceeded (found \{self.breakpoint_count}). This breakpoint will be ignored.",
          ),
        )
        None
      } else {
        Some(value)
      }
    }
  }
}

///|
fn AnthropicCacheControlValidator::diagnostics(
  self : AnthropicCacheControlValidator,
) -> Array[@provider.Warning] {
  self.warnings.copy()
}
