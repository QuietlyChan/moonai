///|
/// One example input for a V4 function tool.
pub(all) struct LanguageModelV4FunctionToolInputExample {
  input : Json
} derive(Debug, Eq)

///|
/// Construct a V4 function-tool input example.
pub fn LanguageModelV4FunctionToolInputExample::new(
  input : Json,
) -> LanguageModelV4FunctionToolInputExample {
  { input, }
}

///|
/// A function tool advertised to a V4 language model.
pub(all) struct LanguageModelV4FunctionTool {
  name : String
  description : String?
  input_schema : Json
  input_examples : Array[LanguageModelV4FunctionToolInputExample]
  strict : Bool?
  provider_options : Map[String, Json]
} derive(Debug, Eq)

///|
/// A provider-defined tool advertised to a V4 language model.
pub(all) struct LanguageModelV4ProviderTool {
  id : String
  name : String
  args : Json
} derive(Debug, Eq)

///|
/// A tool available to a V4 language model.
pub(all) enum LanguageModelV4Tool {
  V4FunctionTool(LanguageModelV4FunctionTool)
  V4ProviderTool(LanguageModelV4ProviderTool)
} derive(Debug, Eq)

///|
/// Construct a V4 function tool.
pub fn LanguageModelV4Tool::function(
  name : String,
  input_schema : Json,
  description? : String,
  input_examples? : Array[Json] = [],
  strict? : Bool,
  provider_options? : Map[String, Json] = Map([]),
) -> LanguageModelV4Tool {
  LanguageModelV4Tool::V4FunctionTool({
    name,
    description,
    input_schema,
    input_examples: [
      for input in input_examples => {
        LanguageModelV4FunctionToolInputExample::new(input)
      }
    ],
    strict,
    provider_options,
  })
}

///|
/// Construct a V4 provider-defined tool.
pub fn LanguageModelV4Tool::provider(
  id~ : String,
  name~ : String,
  args? : Json = Json::empty_object(),
) -> LanguageModelV4Tool {
  LanguageModelV4Tool::V4ProviderTool({ id, name, args })
}

///|
/// Return the caller-visible name of a V4 tool.
pub fn LanguageModelV4Tool::name(self : LanguageModelV4Tool) -> String {
  match self {
    LanguageModelV4Tool::V4FunctionTool(value) => value.name
    LanguageModelV4Tool::V4ProviderTool(value) => value.name
  }
}

///|
/// Return whether a V4 function tool requests strict schema generation.
pub fn LanguageModelV4Tool::strict(self : LanguageModelV4Tool) -> Bool {
  match self {
    LanguageModelV4Tool::V4FunctionTool(value) => value.strict.unwrap_or(false)
    LanguageModelV4Tool::V4ProviderTool(_) => false
  }
}

///|
/// Return the optional strict setting of a V4 function tool.
pub fn LanguageModelV4Tool::strict_setting(self : LanguageModelV4Tool) -> Bool? {
  match self {
    LanguageModelV4Tool::V4FunctionTool(value) => value.strict
    LanguageModelV4Tool::V4ProviderTool(_) => None
  }
}

///|
/// Return the optional description of a V4 function tool.
pub fn LanguageModelV4Tool::description(self : LanguageModelV4Tool) -> String? {
  match self {
    LanguageModelV4Tool::V4FunctionTool(value) => value.description
    LanguageModelV4Tool::V4ProviderTool(_) => None
  }
}

///|
/// How a V4 language model should select from its available tools.
pub(all) enum LanguageModelV4ToolChoice {
  V4ToolChoiceAuto
  V4ToolChoiceNone
  V4ToolChoiceRequired
  V4ToolChoiceTool(String)
} derive(Debug, Eq)

///|
/// Convert a legacy tool definition to the V4 tool contract.
pub fn LanguageModelV4Tool::from_tool_definition(
  tool : ToolDefinition,
) -> LanguageModelV4Tool {
  match tool {
    ToolDefinition::FunctionTool(
      name~,
      description~,
      input_schema~,
      input_examples~,
      strict~,
      provider_options~
    ) =>
      LanguageModelV4Tool::V4FunctionTool({
        name,
        description,
        input_schema,
        input_examples: [
          for input in input_examples => {
            LanguageModelV4FunctionToolInputExample::new(input)
          }
        ],
        strict,
        provider_options,
      })
    ToolDefinition::ProviderTool(id~, name~, args~) =>
      LanguageModelV4Tool::V4ProviderTool({ id, name, args })
  }
}

///|
/// Convert a V4 tool to the normalized legacy provider representation.
pub fn LanguageModelV4Tool::to_tool_definition(
  self : LanguageModelV4Tool,
) -> ToolDefinition {
  match self {
    LanguageModelV4Tool::V4FunctionTool(value) =>
      ToolDefinition::FunctionTool(
        name=value.name,
        description=value.description,
        input_schema=value.input_schema,
        input_examples=[ for example in value.input_examples => example.input ],
        strict=value.strict,
        provider_options=copy_provider_metadata(value.provider_options),
      )
    LanguageModelV4Tool::V4ProviderTool(value) =>
      ToolDefinition::ProviderTool(
        id=value.id,
        name=value.name,
        args=value.args,
      )
  }
}

///|
/// Convert legacy tool definitions to independent V4 tool values.
pub fn LanguageModelV4Tool::from_tool_definitions(
  tools : Array[ToolDefinition],
) -> Array[LanguageModelV4Tool] {
  [
    for tool in tools => LanguageModelV4Tool::from_tool_definition(tool)
  ]
}

///|
/// Convert V4 tools to the normalized legacy provider representation.
pub fn LanguageModelV4Tool::to_tool_definitions(
  tools : Array[LanguageModelV4Tool],
) -> Array[ToolDefinition] {
  [
    for tool in tools => tool.to_tool_definition()
  ]
}

///|
/// Convert a legacy tool choice to the V4 contract.
pub fn LanguageModelV4ToolChoice::from_tool_choice(
  choice : ToolChoice,
) -> LanguageModelV4ToolChoice {
  match choice {
    Auto => V4ToolChoiceAuto
    NoTool => V4ToolChoiceNone
    Required => V4ToolChoiceRequired
    Named(name) => V4ToolChoiceTool(name)
  }
}

///|
/// Convert a V4 tool choice to the normalized legacy representation.
pub fn LanguageModelV4ToolChoice::to_tool_choice(
  self : LanguageModelV4ToolChoice,
) -> ToolChoice {
  match self {
    V4ToolChoiceAuto => Auto
    V4ToolChoiceNone => NoTool
    V4ToolChoiceRequired => Required
    V4ToolChoiceTool(name) => Named(name)
  }
}
