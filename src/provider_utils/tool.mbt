///|
/// Options passed to a high-level tool execution callback.
///
/// Provider packages never see this type. They receive the normalized
/// `LanguageModelV4Tool` produced from a `Tool` at the `ai` boundary.
pub(all) struct ToolExecutionOptions {
  tool_call_id : String
  messages : Array[ModelMessage]
  cancellation_token : @provider.CancellationToken?
  context : Json
  experimental_sandbox : SandboxSession?
}

///|
/// Construct tool execution options.
pub fn ToolExecutionOptions::new(
  tool_call_id~ : String,
  messages? : Array[ModelMessage] = [],
  cancellation_token? : @provider.CancellationToken,
  context? : Json = Json::empty_object(),
  experimental_sandbox? : SandboxSession,
) -> ToolExecutionOptions {
  {
    tool_call_id,
    messages: messages.copy(),
    cancellation_token,
    context,
    experimental_sandbox,
  }
}

///|
/// Normalized MoonBit tool execution callback.
pub type ToolExecuteFunction = async (Json, ToolExecutionOptions) -> Json

///|
/// Options passed to a tool-defined approval resolver.
pub(all) struct ToolNeedsApprovalOptions {
  tool_call_id : String
  messages : Array[ModelMessage]
  context : Json
}

///|
/// Construct tool-defined approval options.
pub fn ToolNeedsApprovalOptions::new(
  tool_call_id~ : String,
  messages? : Array[ModelMessage] = [],
  context? : Json = Json::empty_object(),
) -> ToolNeedsApprovalOptions {
  { tool_call_id, messages: messages.copy(), context }
}

///|
/// Dynamically determine whether a validated tool call needs approval.
pub type ToolNeedsApprovalFunction = async (Json, ToolNeedsApprovalOptions) -> Bool

///|
/// Static or input-dependent tool approval configuration.
pub(all) enum ToolNeedsApproval {
  ToolApprovalRequired(Bool)
  ToolApprovalRequiredWhen(ToolNeedsApprovalFunction)
}

///|
/// Construct a static tool approval requirement.
pub fn ToolNeedsApproval::value(required : Bool) -> ToolNeedsApproval {
  ToolApprovalRequired(required)
}

///|
/// Construct an input-dependent tool approval requirement.
pub fn ToolNeedsApproval::when(
  resolve : ToolNeedsApprovalFunction,
) -> ToolNeedsApproval {
  ToolApprovalRequiredWhen(resolve)
}

///|
/// Callback invoked when the model starts producing a tool input.
pub type ToolInputStartFunction = async (ToolExecutionOptions) -> Unit

///|
/// Options passed to a streaming tool-input delta callback.
pub(all) struct ToolInputDeltaOptions {
  input_text_delta : String
  tool_call_id : String
  messages : Array[ModelMessage]
  cancellation_token : @provider.CancellationToken?
  context : Json
  experimental_sandbox : SandboxSession?
}

///|
/// Construct streaming tool-input delta options.
pub fn ToolInputDeltaOptions::new(
  input_text_delta~ : String,
  tool_call_id~ : String,
  messages? : Array[ModelMessage] = [],
  cancellation_token? : @provider.CancellationToken,
  context? : Json = Json::empty_object(),
  experimental_sandbox? : SandboxSession,
) -> ToolInputDeltaOptions {
  {
    input_text_delta,
    tool_call_id,
    messages: messages.copy(),
    cancellation_token,
    context,
    experimental_sandbox,
  }
}

///|
/// Callback invoked for each streamed fragment of a tool input.
pub type ToolInputDeltaFunction = async (ToolInputDeltaOptions) -> Unit

///|
/// Options passed when a complete, validated tool input becomes available.
pub(all) struct ToolInputAvailableOptions {
  input : Json
  tool_call_id : String
  messages : Array[ModelMessage]
  cancellation_token : @provider.CancellationToken?
  context : Json
  experimental_sandbox : SandboxSession?
}

///|
/// Construct complete tool-input options.
pub fn ToolInputAvailableOptions::new(
  input~ : Json,
  tool_call_id~ : String,
  messages? : Array[ModelMessage] = [],
  cancellation_token? : @provider.CancellationToken,
  context? : Json = Json::empty_object(),
  experimental_sandbox? : SandboxSession,
) -> ToolInputAvailableOptions {
  {
    input,
    tool_call_id,
    messages: messages.copy(),
    cancellation_token,
    context,
    experimental_sandbox,
  }
}

///|
/// Callback invoked when a complete, validated tool input is available.
pub type ToolInputAvailableFunction = async (ToolInputAvailableOptions) -> Unit

///|
/// Inputs passed to a tool's model-output conversion callback.
pub(all) struct ToolModelOutputOptions {
  tool_call_id : String
  input : Json
  output : Json
}

///|
/// Construct model-output conversion options.
pub fn ToolModelOutputOptions::new(
  tool_call_id~ : String,
  input~ : Json,
  output~ : Json,
) -> ToolModelOutputOptions {
  { tool_call_id, input, output }
}

///|
/// Convert a tool's application output into the shape sent back to a model.
pub type ToolModelOutputFunction = async (ToolModelOutputOptions) -> ModelToolResultOutput

///|
/// A named set of high-level tools.
///
/// The map key is the name advertised to the model, matching AI SDK's
/// `ToolSet` object keys. A tool value intentionally does not own its name.
pub type ToolSet = Map[String, Tool]

///|
/// Late binding callback used by a local caller tool.
pub type LocalToolCallerBinder = (ToolSet) -> Tool

///|
/// Provider-options transformation used by a provider caller tool.
pub type ProviderToolCallerOptionsPreparer = (Map[String, Json]) -> Map[
  String,
  Json,
]

///|
/// Additional behavior attached to a tool that can call other tools.
pub(all) enum ToolCallerDefinition {
  LocalToolCaller(LocalToolCallerBinder)
  ProviderToolCaller(ProviderToolCallerOptionsPreparer)
}

///|
/// Construct a local caller definition.
pub fn ToolCallerDefinition::local_caller(
  bind : LocalToolCallerBinder,
) -> ToolCallerDefinition {
  LocalToolCaller(bind)
}

///|
/// Construct a provider caller definition.
pub fn ToolCallerDefinition::provider(
  prepare_provider_options : ProviderToolCallerOptionsPreparer,
) -> ToolCallerDefinition {
  ProviderToolCaller(prepare_provider_options)
}

///|
/// Return whether this caller is bound and executed locally.
pub fn ToolCallerDefinition::is_local(self : ToolCallerDefinition) -> Bool {
  self is LocalToolCaller(_)
}

///|
/// Return whether this caller is implemented by the model provider.
pub fn ToolCallerDefinition::is_provider(self : ToolCallerDefinition) -> Bool {
  self is ProviderToolCaller(_)
}

///|
/// Bind tools to a local caller. Provider callers return `None`.
pub fn ToolCallerDefinition::bind(
  self : ToolCallerDefinition,
  tools : ToolSet,
) -> Tool? {
  match self {
    LocalToolCaller(bind) => Some(bind(copy_tool_set(tools)))
    ProviderToolCaller(_) => None
  }
}

///|
/// Prepare provider options for a callee. Local callers preserve the input.
pub fn ToolCallerDefinition::prepare_provider_options(
  self : ToolCallerDefinition,
  provider_options : Map[String, Json],
) -> Map[String, Json] {
  match self {
    ProviderToolCaller(prepare) =>
      prepare(copy_json_map_for_tool(provider_options))
    LocalToolCaller(_) => copy_json_map_for_tool(provider_options)
  }
}

///|
/// Context used to resolve a function tool description for one model step.
pub(all) struct ToolDescriptionOptions {
  context : Json
  experimental_sandbox : SandboxSession?
}

///|
/// Construct dynamic tool-description options.
pub fn ToolDescriptionOptions::new(
  context? : Json = Json::empty_object(),
  experimental_sandbox? : SandboxSession,
) -> ToolDescriptionOptions {
  { context, experimental_sandbox }
}

///|
/// Callback that derives a tool description from step context and sandbox.
pub type ToolDescriptionFunction = (ToolDescriptionOptions) -> String

///|
/// User-facing high-level tool definition.
///
/// This owns execution and caller behavior. The provider package's
/// `ToolDefinition` remains a transport-only value and is created only when a
/// high-level workflow prepares a model call.
pub struct Tool {
  priv definition : @provider.ToolDefinition
  priv input_schema : Json?
  priv output_schema : Json?
  priv metadata : Map[String, Json]
  priv description_callback : ToolDescriptionFunction?
  priv execute_callback : ToolExecuteFunction?
  priv needs_approval : ToolNeedsApproval?
  priv model_output_callback : ToolModelOutputFunction?
  priv input_start_callback : ToolInputStartFunction?
  priv input_delta_callback : ToolInputDeltaFunction?
  priv input_available_callback : ToolInputAvailableFunction?
  priv provider_executed : Bool
  priv supports_deferred_results : Bool
  priv dynamic : Bool
  priv tool_caller : ToolCallerDefinition?
}

///|
fn copy_json_map_for_tool(values : Map[String, Json]) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for entry in values.iter2() {
    result[entry.0] = entry.1
  }
  result
}

///|
/// Construct a function-style tool.
pub fn Tool::function(
  input_schema : Json,
  description? : String,
  description_resolver? : ToolDescriptionFunction,
  output_schema? : Json,
  input_examples? : Array[Json] = [],
  strict? : Bool,
  provider_options? : Map[String, Json] = Map([]),
  metadata? : Map[String, Json] = Map([]),
  execute? : ToolExecuteFunction,
  needs_approval? : ToolNeedsApproval,
  to_model_output? : ToolModelOutputFunction,
  on_input_start? : ToolInputStartFunction,
  on_input_delta? : ToolInputDeltaFunction,
  on_input_available? : ToolInputAvailableFunction,
) -> Tool {
  {
    definition: @provider.ToolDefinition::new(
      "",
      input_schema,
      description?,
      input_examples~,
      strict?,
      provider_options~,
    ),
    input_schema: Some(input_schema),
    output_schema,
    metadata: copy_json_map_for_tool(metadata),
    description_callback: description_resolver,
    execute_callback: execute,
    needs_approval,
    model_output_callback: to_model_output,
    input_start_callback: on_input_start,
    input_delta_callback: on_input_delta,
    input_available_callback: on_input_available,
    provider_executed: false,
    supports_deferred_results: false,
    dynamic: false,
    tool_caller: None,
  }
}

///|
/// Define a function-style high-level tool.
pub fn tool(
  input_schema : Json,
  description? : String,
  description_resolver? : ToolDescriptionFunction,
  output_schema? : Json,
  input_examples? : Array[Json] = [],
  strict? : Bool,
  provider_options? : Map[String, Json] = Map([]),
  metadata? : Map[String, Json] = Map([]),
  execute? : ToolExecuteFunction,
  needs_approval? : ToolNeedsApproval,
  to_model_output? : ToolModelOutputFunction,
  on_input_start? : ToolInputStartFunction,
  on_input_delta? : ToolInputDeltaFunction,
  on_input_available? : ToolInputAvailableFunction,
) -> Tool {
  Tool::function(
    input_schema,
    description?,
    description_resolver?,
    output_schema?,
    input_examples~,
    strict?,
    provider_options~,
    metadata~,
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Construct a function tool whose schema is known only at runtime.
pub fn Tool::dynamic(
  input_schema : Json,
  description? : String,
  description_resolver? : ToolDescriptionFunction,
  output_schema? : Json,
  provider_options? : Map[String, Json] = Map([]),
  metadata? : Map[String, Json] = Map([]),
  execute? : ToolExecuteFunction,
  needs_approval? : ToolNeedsApproval,
  to_model_output? : ToolModelOutputFunction,
  on_input_start? : ToolInputStartFunction,
  on_input_delta? : ToolInputDeltaFunction,
  on_input_available? : ToolInputAvailableFunction,
) -> Tool {
  let tool = Tool::function(
    input_schema,
    description?,
    description_resolver?,
    output_schema?,
    provider_options~,
    metadata~,
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
  { ..tool, dynamic: true }
}

///|
/// Define a dynamically described function tool.
pub fn dynamic_tool(
  input_schema : Json,
  description? : String,
  description_resolver? : ToolDescriptionFunction,
  output_schema? : Json,
  provider_options? : Map[String, Json] = Map([]),
  metadata? : Map[String, Json] = Map([]),
  execute? : ToolExecuteFunction,
  needs_approval? : ToolNeedsApproval,
  to_model_output? : ToolModelOutputFunction,
  on_input_start? : ToolInputStartFunction,
  on_input_delta? : ToolInputDeltaFunction,
  on_input_available? : ToolInputAvailableFunction,
) -> Tool {
  Tool::dynamic(
    input_schema,
    description?,
    description_resolver?,
    output_schema?,
    provider_options~,
    metadata~,
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// AI SDK-style camel-case spelling for `dynamic_tool`.
pub fn dynamicTool(
  input_schema : Json,
  description? : String,
  description_resolver? : ToolDescriptionFunction,
  output_schema? : Json,
  provider_options? : Map[String, Json] = Map([]),
  metadata? : Map[String, Json] = Map([]),
  execute? : ToolExecuteFunction,
  needs_approval? : ToolNeedsApproval,
  to_model_output? : ToolModelOutputFunction,
  on_input_start? : ToolInputStartFunction,
  on_input_delta? : ToolInputDeltaFunction,
  on_input_available? : ToolInputAvailableFunction,
) -> Tool {
  dynamic_tool(
    input_schema,
    description?,
    description_resolver?,
    output_schema?,
    provider_options~,
    metadata~,
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Construct a provider-defined tool.
pub fn Tool::provider(
  id~ : String,
  args? : Json = Json::empty_object(),
  input_schema? : Json,
  output_schema? : Json,
  metadata? : Map[String, Json] = Map([]),
  provider_executed? : Bool = true,
  supports_deferred_results? : Bool = false,
  execute? : ToolExecuteFunction,
  needs_approval? : ToolNeedsApproval,
  to_model_output? : ToolModelOutputFunction,
  on_input_start? : ToolInputStartFunction,
  on_input_delta? : ToolInputDeltaFunction,
  on_input_available? : ToolInputAvailableFunction,
) -> Tool {
  {
    definition: @provider.ToolDefinition::provider(id~, name="", args~),
    input_schema,
    output_schema,
    metadata: copy_json_map_for_tool(metadata),
    description_callback: None,
    execute_callback: execute,
    needs_approval,
    model_output_callback: to_model_output,
    input_start_callback: on_input_start,
    input_delta_callback: on_input_delta,
    input_available_callback: on_input_available,
    provider_executed,
    supports_deferred_results,
    dynamic: false,
    tool_caller: None,
  }
}

///|
/// Lift an existing provider transport definition into a high-level tool.
pub fn Tool::from_tool_definition(
  definition : @provider.ToolDefinition,
  output_schema? : Json,
  metadata? : Map[String, Json] = Map([]),
  provider_executed? : Bool = false,
  supports_deferred_results? : Bool = false,
  execute? : ToolExecuteFunction,
  needs_approval? : ToolNeedsApproval,
  to_model_output? : ToolModelOutputFunction,
  on_input_start? : ToolInputStartFunction,
  on_input_delta? : ToolInputDeltaFunction,
  on_input_available? : ToolInputAvailableFunction,
) -> Tool {
  {
    definition,
    input_schema: match definition {
      @provider.FunctionTool(input_schema~, ..) => Some(input_schema)
      @provider.ProviderTool(..) => None
    },
    output_schema,
    metadata: copy_json_map_for_tool(metadata),
    description_callback: None,
    execute_callback: execute,
    needs_approval,
    model_output_callback: to_model_output,
    input_start_callback: on_input_start,
    input_delta_callback: on_input_delta,
    input_available_callback: on_input_available,
    provider_executed,
    supports_deferred_results,
    dynamic: false,
    tool_caller: None,
  }
}

///|
/// Attach caller behavior without mutating the original tool.
pub fn Tool::with_tool_caller(
  self : Tool,
  definition : ToolCallerDefinition,
) -> Tool {
  { ..self, tool_caller: Some(definition) }
}

///|
/// AI SDK-style helper for attaching experimental caller behavior.
pub fn experimental_tool_caller(
  tool : Tool,
  definition : ToolCallerDefinition,
) -> Tool {
  tool.with_tool_caller(definition)
}

///|
/// Camel-case spelling for `experimental_tool_caller`.
pub fn experimentalToolCaller(
  tool : Tool,
  definition : ToolCallerDefinition,
) -> Tool {
  experimental_tool_caller(tool, definition)
}

///|
/// Return caller behavior attached to a tool.
pub fn experimental_get_tool_caller(tool : Tool) -> ToolCallerDefinition? {
  tool.tool_caller
}

///|
/// Camel-case spelling for `experimental_get_tool_caller`.
pub fn experimentalGetToolCaller(tool : Tool) -> ToolCallerDefinition? {
  experimental_get_tool_caller(tool)
}

///|
/// Return whether this tool has an execution callback.
pub fn Tool::is_executable(self : Tool) -> Bool {
  self.execute_callback is Some(_)
}

///|
/// AI SDK-style predicate for executable tools.
pub fn is_executable_tool(tool : Tool) -> Bool {
  tool.is_executable()
}

///|
/// Camel-case spelling for `is_executable_tool`.
pub fn isExecutableTool(tool : Tool) -> Bool {
  is_executable_tool(tool)
}

///|
/// Execute the tool when an execution callback is present.
pub async fn Tool::execute(
  self : Tool,
  input : Json,
  options : ToolExecutionOptions,
) -> Json? {
  match self.execute_callback {
    Some(execute) => Some(execute(input, options))
    None => None
  }
}

///|
/// Resolve the deprecated tool-local approval configuration when present.
pub async fn Tool::resolve_needs_approval(
  self : Tool,
  input : Json,
  options : ToolNeedsApprovalOptions,
) -> Bool? {
  match self.needs_approval {
    Some(ToolApprovalRequired(value)) => Some(value)
    Some(ToolApprovalRequiredWhen(resolve)) => Some(resolve(input, options))
    None => None
  }
}

///|
/// Convert an application tool result to the output shape sent to the model.
///
/// AI SDK defaults string results to text and all other JSON values to JSON.
pub async fn Tool::to_model_output(
  self : Tool,
  options : ToolModelOutputOptions,
) -> ModelToolResultOutput {
  match self.model_output_callback {
    Some(callback) => callback(options)
    None =>
      match options.output {
        String(value) => ModelToolResultOutput::text(value)
        value => ModelToolResultOutput::json(value)
      }
  }
}

///|
/// Invoke the tool-input start callback when one is configured.
pub async fn Tool::invoke_input_start(
  self : Tool,
  options : ToolExecutionOptions,
) -> Unit {
  match self.input_start_callback {
    Some(callback) => callback(options)
    None => ()
  }
}

///|
/// Invoke the streaming tool-input delta callback when one is configured.
pub async fn Tool::invoke_input_delta(
  self : Tool,
  options : ToolInputDeltaOptions,
) -> Unit {
  match self.input_delta_callback {
    Some(callback) => callback(options)
    None => ()
  }
}

///|
/// Invoke the complete tool-input callback when one is configured.
pub async fn Tool::invoke_input_available(
  self : Tool,
  options : ToolInputAvailableOptions,
) -> Unit {
  match self.input_available_callback {
    Some(callback) => callback(options)
    None => ()
  }
}

///|
/// Return the optional output schema.
pub fn Tool::output_schema(self : Tool) -> Json? {
  self.output_schema
}

///|
/// Return the input schema used for local validation when available.
pub fn Tool::input_schema(self : Tool) -> Json? {
  self.input_schema
}

///|
/// Return immutable tool metadata as an independent map.
pub fn Tool::metadata(self : Tool) -> Map[String, Json] {
  copy_json_map_for_tool(self.metadata)
}

///|
/// Return whether the tool is provider executed.
pub fn Tool::is_provider_executed(self : Tool) -> Bool {
  self.provider_executed
}

///|
/// Return whether delayed provider results are supported.
pub fn Tool::supports_deferred_results(self : Tool) -> Bool {
  self.supports_deferred_results
}

///|
/// Return whether this is a dynamically described function tool.
pub fn Tool::is_dynamic(self : Tool) -> Bool {
  self.dynamic
}

///|
/// Return provider options attached to a function tool.
pub fn Tool::provider_options(self : Tool) -> Map[String, Json] {
  match self.definition {
    @provider.FunctionTool(provider_options~, ..) =>
      copy_json_map_for_tool(provider_options)
    @provider.ProviderTool(..) => Map([])
  }
}

///|
/// Resolve a dynamic function-tool description for one model step.
///
/// The returned tool preserves execution callbacks and all other behavior;
/// only the transport definition's description is replaced.
pub fn Tool::resolve_description(
  self : Tool,
  context? : Json = Json::empty_object(),
  experimental_sandbox? : SandboxSession,
) -> Tool {
  guard self.description_callback is Some(resolve) else { return self }
  let description = resolve(
    ToolDescriptionOptions::new(context~, experimental_sandbox?),
  )
  let definition = match self.definition {
    @provider.FunctionTool(
      name~,
      input_schema~,
      input_examples~,
      strict~,
      provider_options~,
      ..
    ) =>
      @provider.FunctionTool(
        name~,
        description=Some(description),
        input_schema~,
        input_examples=input_examples.copy(),
        strict~,
        provider_options=copy_json_map_for_tool(provider_options),
      )
    @provider.ProviderTool(..) => self.definition
  }
  { ..self, definition, }
}

///|
/// AI SDK-style spelling for `resolve_description`.
pub fn Tool::resolveDescription(
  self : Tool,
  context? : Json = Json::empty_object(),
  experimental_sandbox? : SandboxSession,
) -> Tool {
  self.resolve_description(context~, experimental_sandbox?)
}

///|
/// Replace function-tool provider options without mutating the original.
pub fn Tool::with_provider_options(
  self : Tool,
  provider_options : Map[String, Json],
) -> Tool {
  let definition = match self.definition {
    @provider.FunctionTool(
      name~,
      description~,
      input_schema~,
      input_examples~,
      strict~,
      ..
    ) =>
      @provider.FunctionTool(
        name~,
        description~,
        input_schema~,
        input_examples=input_examples.copy(),
        strict~,
        provider_options=copy_json_map_for_tool(provider_options),
      )
    @provider.ProviderTool(..) => self.definition
  }
  { ..self, definition, }
}

///|
/// Convert a high-level tool to the provider transport definition.
pub fn Tool::to_tool_definition(
  self : Tool,
  name : String,
) -> @provider.ToolDefinition {
  match self.definition {
    @provider.FunctionTool(
      description~,
      input_schema~,
      input_examples~,
      strict~,
      provider_options~,
      ..
    ) =>
      @provider.FunctionTool(
        name~,
        description~,
        input_schema~,
        input_examples=input_examples.copy(),
        strict~,
        provider_options=copy_json_map_for_tool(provider_options),
      )
    @provider.ProviderTool(id~, args~, ..) =>
      @provider.ProviderTool(id~, name~, args~)
  }
}

///|
/// Create a named tool set while preserving insertion order.
pub fn tool_set(entries : Array[(String, Tool)]) -> ToolSet {
  Map(entries)
}

///|
/// AI SDK-style camel-case spelling for `tool_set`.
pub fn toolSet(entries : Array[(String, Tool)]) -> ToolSet {
  tool_set(entries)
}

///|
/// Return an independent shallow copy of a tool set.
pub fn copy_tool_set(tools : ToolSet) -> ToolSet {
  let result : ToolSet = Map([])
  for entry in tools.iter2() {
    result[entry.0] = entry.1
  }
  result
}

///|
/// Convert named high-level tools to provider transport definitions.
pub fn tool_definitions(tools : ToolSet) -> Array[@provider.ToolDefinition] {
  [
    for entry in tools.iter2() => entry.1.to_tool_definition(entry.0)
  ]
}
