///|
test "Anthropic response metadata exposes typed usage iterations" {
  let metadata = decode_anthropic_message_metadata({
    "usage": {
      "input_tokens": 12,
      "iterations": [
        {
          "type": "message",
          "model": "claude-sonnet",
          "input_tokens": 8,
          "output_tokens": 4,
          "cache_creation_input_tokens": 2,
        },
      ],
    },
    "stop_sequence": null,
    "stop_details": {
      "type": "refusal",
      "category": "safety",
      "recommended_model": "claude-opus",
    },
    "container": {
      "id": "container-1",
      "expires_at": "2030-01-01T00:00:00Z",
      "skills": [
        { "type": "custom", "skill_id": "skill-1", "version": "latest" },
      ],
    },
    "context_management": {
      "applied_edits": [
        { "type": "clear_tool_uses_20250919", "cleared_tool_uses": 2 },
      ],
    },
  })
  assert_true(metadata is Some(_))
  match metadata {
    Some(value) => {
      assert_eq(value.stop_sequence, None)
      assert_eq(value.iterations.unwrap().length(), 1)
      assert_eq(value.iterations.unwrap()[0].kind, "message")
      assert_eq(value.iterations.unwrap()[0].input_tokens, 8)
      assert_eq(
        value.stop_details.unwrap().recommended_model,
        Some("claude-opus"),
      )
      assert_eq(value.container.unwrap().skills.unwrap()[0].skill_id, "skill-1")
      assert_eq(
        value.context_management.unwrap().applied_edits[0].cleared_tool_uses,
        Some(2),
      )
    }
    None => fail("expected typed Anthropic metadata")
  }
}

///|
test "Anthropic metadata parser accepts event wrappers and camel case" {
  let metadata = decodeAnthropicMessageMetadata({
    "message": {
      "usage": { "iterations": null },
      "stopSequence": "DONE",
      "contextManagement": { "appliedEdits": [] },
    },
  }).unwrap()
  assert_eq(metadata.stop_sequence, Some("DONE"))
  assert_eq(metadata.iterations, None)
  assert_eq(metadata.context_management.unwrap().applied_edits.length(), 0)
}

///|
test "empty Anthropic metadata returns none" {
  assert_true(decode_anthropic_message_metadata({ "id": "msg_1" }) is None)
}
