///|
test "tool approval signatures match the AI SDK text-secret vector" {
  let input : Json = { "path": "/tmp/cache" }
  let secret = ToolApprovalSecret::string("test-secret-key-for-hmac-signing")
  assert_eq(canonical_json(input), "{\"path\":\"/tmp/cache\"}")
  assert_eq(
    hash_canonical(input),
    "z6DfQ9QDa112neoYXpvHbdMcFAzyM-8SXyI_2NogPUA",
  )
  let signature = sign_tool_approval(
    secret, "approval-1", "call-1", "deleteFile", input,
  )
  assert_eq(signature, "KhhdqErvPwq9PCD-YYlVKgPDJ_tby36fpqptjJpmYhE")
  assert_true(
    verify_tool_approval_signature(
      secret, signature, "approval-1", "call-1", "deleteFile", input,
    ),
  )
}

///|
test "tool approval signatures canonicalize nested objects and raw keys" {
  let input : Json = {
    "z": [true, null, "snow"],
    "a": { "beta": 2, "alpha": 1 },
  }
  let secret = ToolApprovalSecret::bytes(b"\x00\x01\x02\x03\xfe\xff")
  assert_eq(
    canonical_json(input),
    "{\"a\":{\"alpha\":1,\"beta\":2},\"z\":[true,null,\"snow\"]}",
  )
  assert_eq(
    hash_canonical(input),
    "9nnF_w-jIGkXgnE62mrUzr80BaogkztxuBAjDFLBONo",
  )
  assert_eq(
    sign_tool_approval(
      secret, "approval-bytes", "call-2", "search\\docs", input,
    ),
    "vwWUsGQmfElf7thr9m7-ux0IecdMJvunjEzuo8FH75g",
  )
}

///|
test "canonical approval JSON follows JavaScript number serialization" {
  assert_eq(
    canonical_json(@json.parse("{\"n\":99999999999999999999999}")),
    "{\"n\":1e+23}",
  )
  assert_eq(canonical_json(@json.parse("{\"n\":1e999}")), "{\"n\":null}")
  assert_eq(canonical_json(@json.parse("{\"n\":-0}")), "{\"n\":0}")
}

///|
test "tool approval verification rejects tampering and malformed signatures" {
  let secret = ToolApprovalSecret::string("test-secret-key-for-hmac-signing")
  let input : Json = { "path": "/tmp/cache" }
  let signature = sign_tool_approval(
    secret, "approval-1", "call-1", "deleteFile", input,
  )
  assert_true(
    !verify_tool_approval_signature(
      secret, signature, "tampered", "call-1", "deleteFile", input,
    ),
  )
  assert_true(
    !verify_tool_approval_signature(
      secret,
      signature,
      "approval-1",
      "call-1",
      "deleteFile",
      { "path": "/app/.env" },
    ),
  )
  assert_true(
    !verify_tool_approval_signature(
      ToolApprovalSecret::string("different-secret"),
      signature,
      "approval-1",
      "call-1",
      "deleteFile",
      input,
    ),
  )
  assert_true(
    !verify_tool_approval_signature(
      secret, "not/base64%", "approval-1", "call-1", "deleteFile", input,
    ),
  )
}

///|
test "tool approval verification accepts safe legacy signatures" {
  let secret = ToolApprovalSecret::string("test-secret-key-for-hmac-signing")
  let input : Json = { "path": "/tmp/cache" }
  let digest = hash_canonical(input)
  let signature = @mooncry.hmac_sha256(
      secret.to_bytes(),
      legacy_approval_signature_payload(
        "approval-1", "call-1", "deleteFile", digest,
      ),
    )
    |> to_base64url
  assert_eq(signature, "m_3hnkZy4Mx-__NmCA7J5NTNUwAk3bhbUtXD7PDAF_k")
  assert_true(
    verify_tool_approval_signature(
      secret, signature, "approval-1", "call-1", "deleteFile", input,
    ),
  )
}

///|
test "tool approval payloads cannot be retupled across newlines" {
  let secret = ToolApprovalSecret::string("newline-secret")
  let input : Json = { "path": "/tmp/target" }
  let signature = sign_tool_approval(
    secret, "approval-1", "call-1", "searchDocs\ndeleteFile", input,
  )
  assert_true(
    !verify_tool_approval_signature(
      secret, signature, "approval-1", "call-1\nsearchDocs", "deleteFile", input,
    ),
  )
  let legacy_signature = @mooncry.hmac_sha256(
      secret.to_bytes(),
      legacy_approval_signature_payload(
        "approval-1",
        "call-1",
        "searchDocs\ndeleteFile",
        hash_canonical(input),
      ),
    )
    |> to_base64url
  assert_true(
    !verify_tool_approval_signature(
      secret, legacy_signature, "approval-1", "call-1\nsearchDocs", "deleteFile",
      input,
    ),
  )
}
