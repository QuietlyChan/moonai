///|
/// Structured output demo: ask for JSON matching a schema, then validate.
/// The demo model always answers with a schema-conformant object, so this
/// runs fully offline.
async fn main {
  println("== MoonAI structured output demo (offline demo model) ==")
  let config = @shared.load_example_config()
  let schema : Json = {
    "type": "object",
    "properties": {
      "answer": { "type": "string" },
      "confidence": { "type": "number" },
    },
    "required": ["answer"],
  }
  let result = @ai.generate_text(
    config.language_model(),
    prompt="What is MoonAI?",
    response_format=@provider.ResponseFormat::json(
      schema~,
      name="moonai-answer",
    ),
  )
  let text = result.text()
  println("raw: \{text}")
  let value = @json.parse(text) catch {
    _ => {
      println("model output was not JSON")
      return
    }
  }
  try @ai.validate_object(schema, value) catch {
    @ai.ObjectValidationError(path~, message~) => {
      println("validation failed at \{path}: \{message}")
      return
    }
  } noraise {
    _ => println("validated: schema-conformant object")
  }
  ignore(config)
}
