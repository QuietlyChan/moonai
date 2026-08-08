///|
/// Shared factory for tools that are executed by a model provider.
///
/// Provider packages keep their typed argument builders locally and use this
/// factory to attach the common schemas and execution semantics at the
/// `provider_utils` boundary.
pub struct ProviderExecutedToolFactory {
  priv id : String
  priv input_schema : Json
  priv output_schema : Json
  priv supports_deferred_results : Bool
}

///|
/// Construct a provider-executed tool factory.
pub fn ProviderExecutedToolFactory::new(
  id~ : String,
  input_schema~ : Json,
  output_schema~ : Json,
  supports_deferred_results? : Bool = false,
) -> ProviderExecutedToolFactory {
  { id, input_schema, output_schema, supports_deferred_results }
}

///|
/// Construct a provider-executed tool from provider-specific arguments.
pub fn ProviderExecutedToolFactory::create(
  self : ProviderExecutedToolFactory,
  args? : Json = Json::empty_object(),
  on_input_start? : ToolInputStartFunction,
  on_input_delta? : ToolInputDeltaFunction,
  on_input_available? : ToolInputAvailableFunction,
) -> Tool {
  Tool::provider(
    id=self.id,
    args~,
    input_schema=self.input_schema,
    output_schema=self.output_schema,
    provider_executed=true,
    supports_deferred_results=self.supports_deferred_results,
    on_input_start?,
    on_input_delta?,
    on_input_available?,
  )
}

///|
/// Create a reusable provider-executed tool factory.
pub fn create_provider_executed_tool_factory(
  id~ : String,
  input_schema~ : Json,
  output_schema~ : Json,
  supports_deferred_results? : Bool = false,
) -> ProviderExecutedToolFactory {
  ProviderExecutedToolFactory::new(
    id~,
    input_schema~,
    output_schema~,
    supports_deferred_results~,
  )
}

///|
/// AI SDK-style camel-case spelling.
pub fn createProviderExecutedToolFactory(
  id~ : String,
  input_schema~ : Json,
  output_schema~ : Json,
  supports_deferred_results? : Bool = false,
) -> ProviderExecutedToolFactory {
  create_provider_executed_tool_factory(
    id~,
    input_schema~,
    output_schema~,
    supports_deferred_results~,
  )
}
