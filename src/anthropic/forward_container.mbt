///|
fn anthropic_container_id_from_metadata(
  provider_metadata : Map[String, Json],
) -> String? {
  let value = match provider_metadata.get("anthropic") {
    Some(value) => Some(value)
    None => provider_metadata.get("anthropic.messages")
  }
  match value {
    Some({ "container": { "id": String(id), .. }, .. }) if id != "" => Some(id)
    _ => None
  }
}

///|
/// Forward the most recent Anthropic container ID into the next call.
///
/// Each array entry is the `provider_metadata` map from one completed step,
/// ordered oldest to newest. The returned map can be passed directly as
/// `ChatCallOptions.provider_options`.
pub fn forward_anthropic_container_id_from_last_step(
  steps : Array[Map[String, Json]],
) -> Map[String, Json]? {
  let mut index = steps.length()
  while index > 0 {
    index = index - 1
    if anthropic_container_id_from_metadata(steps[index]) is Some(id) {
      return Some(
        AnthropicLanguageModelOptions::new(
          container=AnthropicContainer::new(id~),
        ).to_provider_options(),
      )
    }
  }
  None
}

///|
/// AI SDK-style spelling for `forward_anthropic_container_id_from_last_step`.
pub fn forwardAnthropicContainerIdFromLastStep(
  steps : Array[Map[String, Json]],
) -> Map[String, Json]? {
  forward_anthropic_container_id_from_last_step(steps)
}
