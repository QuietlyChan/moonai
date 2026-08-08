///|
/// Invoke lifecycle callbacks for one provider stream event.
///
/// The public stream event is delivered before this function is called. Tool
/// names are retained from input-start events because delta and ready events
/// are correlated by call ID, matching AI SDK's stream transform.
async fn invoke_tool_callbacks_from_stream_part(
  event : @provider.LanguageModelV4StreamPart,
  tools : @provider_utils.ToolSet,
  ongoing_tool_call_names : Map[String, String],
  messages : Array[@provider_utils.ModelMessage],
  cancellation_token : @provider.CancellationToken?,
  runtime_context : Json,
  experimental_sandbox : @provider_utils.SandboxSession?,
) -> Unit {
  match event {
    @provider.V4ToolInputStart(id~, tool_name~, ..) => {
      ongoing_tool_call_names[id] = tool_name
      match tools.get(tool_name) {
        Some(tool) =>
          tool.invoke_input_start(
            @provider_utils.ToolExecutionOptions::new(
              tool_call_id=id,
              messages~,
              cancellation_token?,
              context=runtime_context,
              experimental_sandbox?,
            ),
          )
        None => ()
      }
    }
    @provider.V4ToolInputDelta(id~, delta~, ..) =>
      match ongoing_tool_call_names.get(id) {
        Some(tool_name) =>
          match tools.get(tool_name) {
            Some(tool) =>
              tool.invoke_input_delta(
                @provider_utils.ToolInputDeltaOptions::new(
                  input_text_delta=delta,
                  tool_call_id=id,
                  messages~,
                  cancellation_token?,
                  context=runtime_context,
                  experimental_sandbox?,
                ),
              )
            None => ()
          }
        None => ()
      }
    @provider.V4ToolCallReady(call) => {
      let tool_name = ongoing_tool_call_names.get(call.tool_call_id)
      ongoing_tool_call_names.remove(call.tool_call_id)
      match tool_name {
        Some(name) =>
          match tools.get(name) {
            Some(tool) => {
              let parsed_call = parse_tool_call(call, tools)
              if !parsed_call.invalid {
                tool.invoke_input_available(
                  @provider_utils.ToolInputAvailableOptions::new(
                    input=parsed_call.input,
                    tool_call_id=call.tool_call_id,
                    messages~,
                    cancellation_token?,
                    context=runtime_context,
                    experimental_sandbox?,
                  ),
                )
              }
            }
            None => ()
          }
        None => ()
      }
    }
    _ => ()
  }
}
