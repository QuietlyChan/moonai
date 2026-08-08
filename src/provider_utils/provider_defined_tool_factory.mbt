///|
/// Shared factory for tools whose protocol is defined by a model provider but
/// whose execution remains under application control.
pub struct ProviderDefinedToolFactory {
  priv id : String
  priv input_schema : Json
  priv output_schema : Json?
}

///|
/// Construct a provider-defined tool factory.
pub fn ProviderDefinedToolFactory::new(
  id~ : String,
  input_schema~ : Json,
  output_schema? : Json,
) -> ProviderDefinedToolFactory {
  { id, input_schema, output_schema }
}

///|
/// Construct a provider-defined tool from provider-specific arguments.
pub fn ProviderDefinedToolFactory::create(
  self : ProviderDefinedToolFactory,
  args? : Json = Json::empty_object(),
  output_schema? : Json,
  execute? : ToolExecuteFunction,
  needs_approval? : ToolNeedsApproval,
  to_model_output? : ToolModelOutputFunction,
  on_input_start? : ToolInputStartFunction,
  on_input_delta? : ToolInputDeltaFunction,
  on_input_available? : ToolInputAvailableFunction,
) -> Tool {
  let resolved_output_schema = match self.output_schema {
    Some(value) => Some(value)
    None => output_schema
  }
  Tool::provider(
    id=self.id,
    args~,
    input_schema=self.input_schema,
    output_schema?=resolved_output_schema,
    provider_executed=false,
    execute?,
    needs_approval?,
    to_model_output?,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create a provider-defined tool factory with a caller-selected output type.
pub fn create_provider_defined_tool_factory(
  id~ : String,
  input_schema~ : Json,
) -> ProviderDefinedToolFactory {
  ProviderDefinedToolFactory::new(id~, input_schema~)
}

///|
/// AI SDK-style camel-case spelling.
pub fn createProviderDefinedToolFactory(
  id~ : String,
  input_schema~ : Json,
) -> ProviderDefinedToolFactory {
  create_provider_defined_tool_factory(id~, input_schema~)
}

///|
/// Create a provider-defined tool factory with a fixed output schema.
pub fn create_provider_defined_tool_factory_with_output_schema(
  id~ : String,
  input_schema~ : Json,
  output_schema~ : Json,
) -> ProviderDefinedToolFactory {
  ProviderDefinedToolFactory::new(id~, input_schema~, output_schema~)
}

///|
/// AI SDK-style camel-case spelling.
pub fn createProviderDefinedToolFactoryWithOutputSchema(
  id~ : String,
  input_schema~ : Json,
  output_schema~ : Json,
) -> ProviderDefinedToolFactory {
  create_provider_defined_tool_factory_with_output_schema(
    id~,
    input_schema~,
    output_schema~,
  )
}
