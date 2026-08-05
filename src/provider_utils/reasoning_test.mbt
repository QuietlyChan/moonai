///|
test "reasoning budget follows AI SDK percentages and clamps bounds" {
  let warnings : Array[@provider.Warning] = []
  assert_eq(
    map_reasoning_to_provider_budget(@provider.Medium, 64_000, 64_000, warnings),
    Some(19_200),
  )
  assert_eq(warnings, [])

  assert_eq(
    map_reasoning_to_provider_budget(
      @provider.Minimal,
      10_000,
      10_000,
      warnings,
    ),
    Some(1_024),
  )
  assert_eq(
    map_reasoning_to_provider_budget(@provider.XHigh, 64_000, 50_000, warnings),
    Some(50_000),
  )
}

///|
test "reasoning utility distinguishes default and disabled" {
  assert_false(is_custom_reasoning(@provider.ProviderDefault))
  assert_true(is_custom_reasoning(@provider.Disabled))
  let warnings : Array[@provider.Warning] = []
  assert_eq(
    map_reasoning_to_provider_budget(
      @provider.Disabled,
      16_384,
      16_384,
      warnings,
    ),
    None,
  )
  assert_eq(warnings, [])
}

///|
test "reasoning effort utility reports compatibility and unsupported levels" {
  let warnings : Array[@provider.Warning] = []
  let mapped = map_reasoning_to_provider_effort(
    @provider.XHigh,
    { "xhigh": "max" },
    warnings,
  )
  assert_eq(mapped, Some("max"))
  assert_true(warnings[0] is @provider.Compatibility(..))

  let missing = map_reasoning_to_provider_effort(
    @provider.High,
    { "low": "low" },
    warnings,
  )
  assert_eq(missing, None)
  assert_true(warnings[1] is @provider.Unsupported(..))
}
