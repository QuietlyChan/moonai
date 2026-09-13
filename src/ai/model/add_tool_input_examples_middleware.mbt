///|
/// Default example formatter: the JSON-stringified example input.
fn default_tool_example_format(
  example : @provider.LanguageModelV4FunctionToolInputExample,
  _index : Int,
) -> String {
  example.input.stringify()
}

///|
/// Tool input-examples middleware.
///
/// Appends input examples to function-tool descriptions for providers that
/// do not natively support the `input_examples` property. The examples are
/// serialized into the description text and (by default) removed from the
/// typed field.
pub fn add_tool_input_examples_middleware(
  prefix? : String = "Input Examples:",
  format? : (@provider.LanguageModelV4FunctionToolInputExample, Int) -> String,
  remove? : Bool = true,
) -> @provider.LanguageModelV4Middleware {
  let format = match format {
    Some(value) => value
    None => default_tool_example_format
  }
  @provider.LanguageModelV4Middleware::new(transform_params=fn(context) {
    let params = context.params
    let mut changed = false
    let tools : Array[@provider.LanguageModelV4Tool] = []
    for tool in params.tools {
      match tool {
        @provider.V4FunctionTool(value) if value.input_examples.length() > 0 => {
          let formatted = StringBuilder()
          for index, example in value.input_examples.iter2() {
            if index > 0 {
              formatted.write_string("\n")
            }
            formatted.write_string(format(example, index))
          }
          let examples_section = "\{prefix}\n\{formatted.to_string()}"
          let description = match value.description {
            Some(existing) => "\{existing}\n\n\{examples_section}"
            None => examples_section
          }
          tools.push(
            @provider.V4FunctionTool({
              ..value,
              description: Some(description),
              input_examples: if remove {
                []
              } else {
                value.input_examples
              },
            }),
          )
          changed = true
        }
        other => tools.push(other)
      }
    }
    if !changed {
      return params
    }
    { ..params, tools, }
  })
}
