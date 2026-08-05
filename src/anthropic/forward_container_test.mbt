///|
test "forward Anthropic container ID searches steps from newest to oldest" {
  let provider_options = forward_anthropic_container_id_from_last_step([
    { "anthropic": { "container": { "id": "container-old" } } },
    { "other": { "container": { "id": "ignored" } } },
    { "anthropic": { "container": { "id": "container-new" } } },
  ])
  match provider_options {
    Some(options) =>
      json_inspect(Json::object(options), content={
        "anthropic": { "container": { "id": "container-new" } },
      })
    None => fail("expected forwarded Anthropic container options")
  }
}

///|
test "forward Anthropic container ID accepts qualified metadata namespace" {
  let provider_options = forwardAnthropicContainerIdFromLastStep([
    { "anthropic.messages": { "container": { "id": "container-qualified" } } },
  ])
  assert_true(provider_options is Some(_))
}

///|
test "forward Anthropic container ID returns none when no step has one" {
  assert_eq(
    forward_anthropic_container_id_from_last_step([
      { "anthropic": { "container": null } },
    ]),
    None,
  )
}
