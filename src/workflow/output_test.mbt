///|
test "workflow output validation accepts schema-conformant text" {
  let spec : WorkflowOutputSpecification = {
    schema: {
      "type": "object",
      "properties": { "answer": { "type": "string" } },
      "required": ["answer"],
    },
    name: Some("answer-spec"),
  }
  let value = validate_workflow_output(
    spec~,
    text="{\"answer\":\"Moon it is\"}",
  )
  assert_eq(value, { "answer": "Moon it is" })
}

///|
test "workflow output validation rejects malformed json and schema drift" {
  let spec : WorkflowOutputSpecification = {
    schema: {
      "type": "object",
      "properties": { "answer": { "type": "string" } },
      "required": ["answer"],
    },
    name: None,
  }
  try validate_workflow_output(spec~, text="not json") catch {
    WorkflowOutputValidationError(message~, text~) => {
      assert_true(message.contains("not valid JSON"))
      assert_eq(text, "not json")
    }
  } noraise {
    _ => fail("expected malformed json rejection")
  }
  try validate_workflow_output(spec~, text="{\"wrong\":1}") catch {
    WorkflowOutputValidationError(message~, ..) =>
      assert_true(message.contains("schema validation"))
  } noraise {
    _ => fail("expected schema rejection")
  }
}
