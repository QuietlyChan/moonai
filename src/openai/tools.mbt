///|
/// Call sites that may invoke an OpenAI function tool.
pub(all) enum OpenAIToolCaller {
  Direct
  Programmatic
} derive(Debug, Eq)

///|
/// A group of function tools that can be discovered through OpenAI tool
/// search.
pub(all) struct OpenAIToolNamespace {
  name : String
  description : String
} derive(Debug, Eq)

///|
/// Construct an OpenAI function-tool namespace.
pub fn OpenAIToolNamespace::new(
  name~ : String,
  description~ : String,
) -> OpenAIToolNamespace {
  { name, description }
}

///|
/// OpenAI-specific options for a provider-neutral function tool.
///
/// Pass `to_provider_options()` to `ToolDefinition::new`. Keeping these
/// options in the OpenAI package mirrors AI SDK's exported
/// `OpenAIToolOptions` without coupling the shared provider contract to
/// OpenAI-specific fields.
pub(all) struct OpenAIToolOptions {
  allowed_callers : Array[OpenAIToolCaller]?
  defer_loading : Bool?
  output_schema : Json?
  tool_namespace : OpenAIToolNamespace?
} derive(Debug, Eq)

///|
/// Construct typed options for an OpenAI function tool.
pub fn OpenAIToolOptions::new(
  allowed_callers? : Array[OpenAIToolCaller],
  defer_loading? : Bool,
  output_schema? : Json,
  tool_namespace? : OpenAIToolNamespace,
) -> OpenAIToolOptions {
  { allowed_callers, defer_loading, output_schema, tool_namespace }
}

///|
fn OpenAIToolCaller::wire_name(self : OpenAIToolCaller) -> String {
  match self {
    Direct => "direct"
    Programmatic => "programmatic"
  }
}

///|
/// Convert typed OpenAI function-tool options into the provider-options map
/// accepted by the shared tool contract.
pub fn OpenAIToolOptions::to_provider_options(
  self : OpenAIToolOptions,
) -> Map[String, Json] {
  let options : Map[String, Json] = Map(
    [
      ..if self.allowed_callers is Some(values) {
        [
          (
            "allowedCallers",
            Json::array(
              [
                for caller in values => Json::string(caller.wire_name())
              ],
            ),
          ),
        ]
      },
      ..if self.defer_loading is Some(value) {
        [("deferLoading", Json::boolean(value))]
      },
      ..if self.output_schema is Some(value) {
        [("outputSchema", value)]
      },
      ..if self.tool_namespace is Some(value) {
        [
          (
            "namespace",
            ({ "name": value.name, "description": value.description } : Json),
          ),
        ]
      },
    ],
  )
  Map([("openai", Json::object(options))])
}

///|
/// Code Interpreter container selection.
pub(all) enum OpenAICodeInterpreterContainer {
  ExistingContainer(String)
  AutoContainer(file_ids~ : Array[String]?)
} derive(Debug, Eq)

///|
/// Select an existing Code Interpreter container by ID.
pub fn OpenAICodeInterpreterContainer::existing(
  container_id : String,
) -> OpenAICodeInterpreterContainer {
  ExistingContainer(container_id)
}

///|
/// Ask OpenAI to create an automatic Code Interpreter container.
pub fn OpenAICodeInterpreterContainer::auto(
  file_ids? : Array[String],
) -> OpenAICodeInterpreterContainer {
  AutoContainer(file_ids~)
}

///|
fn OpenAICodeInterpreterContainer::to_args_json(
  self : OpenAICodeInterpreterContainer,
) -> Json {
  match self {
    ExistingContainer(container_id) => Json::string(container_id)
    AutoContainer(file_ids~) =>
      Json::object(
        Map(
          [
            ..if file_ids is Some(values) {
              [
                (
                  "fileIds",
                  Json::array([ for value in values => Json::string(value) ]),
                ),
              ]
            },
          ],
        ),
      )
  }
}

///|
/// Memory limit for an OpenAI-managed shell container.
pub(all) enum OpenAIShellMemoryLimit {
  Memory1G
  Memory4G
  Memory16G
  Memory64G
} derive(Debug, Eq)

///|
fn OpenAIShellMemoryLimit::wire_name(self : OpenAIShellMemoryLimit) -> String {
  match self {
    Memory1G => "1g"
    Memory4G => "4g"
    Memory16G => "16g"
    Memory64G => "64g"
  }
}

///|
/// A secret exposed only to one domain in a shell network allowlist.
pub(all) struct OpenAIShellDomainSecret {
  domain : String
  name : String
  value : String
} derive(Debug, Eq)

///|
/// Construct a domain-scoped shell secret.
pub fn OpenAIShellDomainSecret::new(
  domain~ : String,
  name~ : String,
  value~ : String,
) -> OpenAIShellDomainSecret {
  { domain, name, value }
}

///|
/// Network access policy for an OpenAI-managed shell container.
pub(all) enum OpenAIShellNetworkPolicy {
  ShellNetworkDisabled
  ShellNetworkAllowlist(
    allowed_domains~ : Array[String],
    domain_secrets~ : Array[OpenAIShellDomainSecret]?
  )
} derive(Debug, Eq)

///|
/// Disable network access for a shell container.
pub fn OpenAIShellNetworkPolicy::disabled() -> OpenAIShellNetworkPolicy {
  ShellNetworkDisabled
}

///|
/// Restrict shell network access to an explicit domain allowlist.
pub fn OpenAIShellNetworkPolicy::allowlist(
  allowed_domains : Array[String],
  domain_secrets? : Array[OpenAIShellDomainSecret],
) -> OpenAIShellNetworkPolicy {
  ShellNetworkAllowlist(allowed_domains~, domain_secrets~)
}

///|
/// A skill installed into an OpenAI-managed shell container.
pub(all) enum OpenAIShellSkill {
  ShellSkillReference(
    provider_reference~ : @provider.ProviderReference,
    version~ : String?
  )
  ShellInlineSkill(name~ : String, description~ : String, data~ : String)
} derive(Debug, Eq)

///|
/// Reference a skill uploaded to one or more providers.
pub fn OpenAIShellSkill::reference(
  provider_reference : @provider.ProviderReference,
  version? : String,
) -> OpenAIShellSkill {
  ShellSkillReference(provider_reference~, version~)
}

///|
/// Define an inline base64-encoded `application/zip` skill.
pub fn OpenAIShellSkill::inline(
  name~ : String,
  description~ : String,
  data~ : String,
) -> OpenAIShellSkill {
  ShellInlineSkill(name~, description~, data~)
}

///|
/// A local skill directory exposed to a client-executed shell.
pub(all) struct OpenAILocalShellSkill {
  name : String
  description : String
  path : String
} derive(Debug, Eq)

///|
/// Construct a local shell skill descriptor.
pub fn OpenAILocalShellSkill::new(
  name~ : String,
  description~ : String,
  path~ : String,
) -> OpenAILocalShellSkill {
  { name, description, path }
}

///|
/// Execution environment for the OpenAI shell tool.
pub(all) enum OpenAIShellEnvironment {
  ShellContainerAuto(
    file_ids~ : Array[String]?,
    memory_limit~ : OpenAIShellMemoryLimit?,
    network_policy~ : OpenAIShellNetworkPolicy?,
    skills~ : Array[OpenAIShellSkill]?
  )
  ShellContainerReference(container_id~ : String)
  ShellLocal(skills~ : Array[OpenAILocalShellSkill]?)
} derive(Debug, Eq)

///|
/// Configure an automatically managed OpenAI shell container.
pub fn OpenAIShellEnvironment::container_auto(
  file_ids? : Array[String],
  memory_limit? : OpenAIShellMemoryLimit,
  network_policy? : OpenAIShellNetworkPolicy,
  skills? : Array[OpenAIShellSkill],
) -> OpenAIShellEnvironment {
  ShellContainerAuto(file_ids~, memory_limit~, network_policy~, skills~)
}

///|
/// Reuse an existing OpenAI shell container.
pub fn OpenAIShellEnvironment::container_reference(
  container_id : String,
) -> OpenAIShellEnvironment {
  ShellContainerReference(container_id~)
}

///|
/// Execute shell calls in a caller-managed local environment.
pub fn OpenAIShellEnvironment::local_environment(
  skills? : Array[OpenAILocalShellSkill],
) -> OpenAIShellEnvironment {
  ShellLocal(skills~)
}

///|
fn openai_string_array_json(values : Array[String]) -> Json {
  Json::array([ for value in values => Json::string(value) ])
}

///|
fn openai_provider_reference_json(
  reference : @provider.ProviderReference,
) -> Json {
  let entries : Map[String, Json] = Map([])
  for provider_name in reference.providers() {
    if reference.get(provider_name) is Some(id) {
      entries[provider_name] = Json::string(id)
    }
  }
  Json::object(entries)
}

///|
fn OpenAIShellNetworkPolicy::to_args_json(
  self : OpenAIShellNetworkPolicy,
) -> Json {
  match self {
    ShellNetworkDisabled => ({ "type": "disabled" } : Json)
    ShellNetworkAllowlist(allowed_domains~, domain_secrets~) =>
      Json::object(
        Map(
          [
            ("type", Json::string("allowlist")),
            ("allowedDomains", openai_string_array_json(allowed_domains)),
            ..if domain_secrets is Some(values) {
              [
                (
                  "domainSecrets",
                  Json::array(
                    [
                      for secret in values => {
                        {
                          "domain": secret.domain,
                          "name": secret.name,
                          "value": secret.value,
                        }
                      }
                    ],
                  ),
                ),
              ]
            },
          ],
        ),
      )
  }
}

///|
fn OpenAIShellSkill::to_args_json(self : OpenAIShellSkill) -> Json {
  match self {
    ShellSkillReference(provider_reference~, version~) =>
      Json::object(
        Map(
          [
            ("type", Json::string("skillReference")),
            (
              "providerReference",
              openai_provider_reference_json(provider_reference),
            ),
            ..if version is Some(value) {
              [("version", Json::string(value))]
            },
          ],
        ),
      )
    ShellInlineSkill(name~, description~, data~) =>
      (
        {
          "type": "inline",
          "name": name,
          "description": description,
          "source": {
            "type": "base64",
            "mediaType": "application/zip",
            "data": data,
          },
        } : Json)
  }
}

///|
fn OpenAIShellEnvironment::to_args_json(self : OpenAIShellEnvironment) -> Json {
  match self {
    ShellContainerAuto(file_ids~, memory_limit~, network_policy~, skills~) =>
      Json::object(
        Map(
          [
            ("type", Json::string("containerAuto")),
            ..if file_ids is Some(values) {
              [("fileIds", openai_string_array_json(values))]
            },
            ..if memory_limit is Some(value) {
              [("memoryLimit", Json::string(value.wire_name()))]
            },
            ..if network_policy is Some(value) {
              [("networkPolicy", value.to_args_json())]
            },
            ..if skills is Some(values) {
              [
                (
                  "skills",
                  Json::array([ for skill in values => skill.to_args_json() ]),
                ),
              ]
            },
          ],
        ),
      )
    ShellContainerReference(container_id~) =>
      ({ "type": "containerReference", "containerId": container_id } : Json)
    ShellLocal(skills~) =>
      Json::object(
        Map(
          [
            ("type", Json::string("local")),
            ..if skills is Some(values) {
              [
                (
                  "skills",
                  Json::array(
                    [
                      for skill in values => {
                        {
                          "name": skill.name,
                          "description": skill.description,
                          "path": skill.path,
                        }
                      }
                    ],
                  ),
                ),
              ]
            },
          ],
        ),
      )
  }
}

///|
fn openai_tool_key_to_snake(value : String) -> String {
  let output = StringBuilder::new(size_hint=value.length() + 4)
  for character in value {
    if character.is_ascii_uppercase() {
      output.write_char('_')
      output.write_char(character.to_ascii_lowercase())
    } else {
      output.write_char(character)
    }
  }
  output.to_string()
}

///|
fn openai_tool_json_to_wire(value : Json) -> Json {
  match value {
    Object(fields) => {
      let mapped : Map[String, Json] = Map([])
      for entry in fields.iter2() {
        let (key, item) = entry
        mapped[openai_tool_key_to_snake(key)] = openai_tool_json_to_wire(item)
      }
      Json::object(mapped)
    }
    Array(values) =>
      Json::array([ for item in values => openai_tool_json_to_wire(item) ])
    other => other
  }
}

///|
fn openai_tool_fields(args : Json, id : String) -> Map[String, Json] raise {
  match openai_tool_json_to_wire(args) {
    Object(fields) => fields
    _ => fail("OpenAI provider tool \{id} arguments must be a JSON object")
  }
}

///|
fn openai_raw_tool_fields(args : Json, id : String) -> Map[String, Json] raise {
  match args {
    Object(fields) => fields
    _ => fail("OpenAI provider tool \{id} arguments must be a JSON object")
  }
}

///|
fn openai_tool_field(
  fields : Map[String, Json],
  camel_name : String,
  snake_name : String,
) -> Json? {
  match fields.get(camel_name) {
    Some(value) => Some(value)
    None => fields.get(snake_name)
  }
}

///|
fn openai_required_tool_string(
  fields : Map[String, Json],
  camel_name : String,
  snake_name : String,
  context : String,
) -> String raise {
  match openai_tool_field(fields, camel_name, snake_name) {
    Some(String(value)) => value
    _ => fail("OpenAI \{context} requires string field '\{camel_name}'")
  }
}

///|
fn openai_optional_tool_string(
  fields : Map[String, Json],
  camel_name : String,
  snake_name : String,
) -> String? raise {
  match openai_tool_field(fields, camel_name, snake_name) {
    Some(String(value)) => Some(value)
    Some(_) => fail("OpenAI tool field '\{camel_name}' must be a string")
    None => None
  }
}

///|
fn openai_code_interpreter_fields(args : Json) -> Map[String, Json] raise {
  let source = openai_raw_tool_fields(args, "openai.code_interpreter")
  let output : Map[String, Json] = Map([])
  match source.get("container") {
    None => output["container"] = { "type": "auto" }
    Some(String(container_id)) =>
      output["container"] = Json::string(container_id)
    Some(Object(container)) => {
      let mapped : Map[String, Json] = Map([("type", Json::string("auto"))])
      match openai_tool_field(container, "fileIds", "file_ids") {
        Some(Array(values)) => mapped["file_ids"] = Json::array(values)
        Some(_) =>
          fail("OpenAI code interpreter container fileIds must be an array")
        None => ()
      }
      output["container"] = Json::object(mapped)
    }
    Some(_) =>
      fail("OpenAI code interpreter container must be a string or object")
  }
  output
}

///|
fn openai_reference_from_json(
  value : Json,
) -> @provider.ProviderReference raise {
  guard value is Object(fields) else {
    fail("OpenAI shell skill providerReference must be an object")
  }
  let entries : Map[String, String] = Map([])
  for entry in fields.iter2() {
    let (provider_name, provider_id) = entry
    match provider_id {
      String(id) => entries[provider_name] = id
      _ => fail("OpenAI shell skill providerReference values must be strings")
    }
  }
  @provider.ProviderReference::new(entries)
}

///|
fn openai_shell_inline_skill(fields : Map[String, Json]) -> Json raise {
  let name = openai_required_tool_string(fields, "name", "name", "inline skill")
  let description = openai_required_tool_string(
    fields, "description", "description", "inline skill",
  )
  guard openai_tool_field(fields, "source", "source") is Some(Object(source)) else {
    fail("OpenAI inline skill requires object field 'source'")
  }
  let source_type = openai_required_tool_string(
    source, "type", "type", "inline skill source",
  )
  guard source_type == "base64" else {
    fail("OpenAI inline skill source type must be 'base64'")
  }
  let media_type = openai_required_tool_string(
    source, "mediaType", "media_type", "inline skill source",
  )
  let data = openai_required_tool_string(
    source, "data", "data", "inline skill source",
  )
  {
    "type": "inline",
    "name": name,
    "description": description,
    "source": { "type": "base64", "media_type": media_type, "data": data },
  }
}

///|
fn openai_shell_skills(value : Json) -> Json raise {
  guard value is Array(skills) else {
    fail("OpenAI shell environment skills must be an array")
  }
  let mapped : Array[Json] = []
  for skill in skills {
    guard skill is Object(fields) else {
      fail("OpenAI shell environment skill must be an object")
    }
    let kind = openai_required_tool_string(
      fields, "type", "type", "shell skill",
    )
    match kind {
      "skillReference" | "skill_reference" => {
        guard openai_tool_field(
            fields, "providerReference", "provider_reference",
          )
          is Some(reference_json) else {
          fail("OpenAI shell skillReference requires providerReference")
        }
        let skill_id = @provider.resolve_provider_reference(
          openai_reference_from_json(reference_json),
          "openai",
        )
        let version = openai_optional_tool_string(fields, "version", "version").unwrap_or(
          "latest",
        )
        mapped.push({
          "type": "skill_reference",
          "skill_id": skill_id,
          "version": version,
        })
      }
      "inline" => mapped.push(openai_shell_inline_skill(fields))
      _ => fail("Unsupported OpenAI shell skill type '\{kind}'")
    }
  }
  Json::array(mapped)
}

///|
fn openai_local_shell_skills(value : Json) -> Json raise {
  guard value is Array(skills) else {
    fail("OpenAI local shell skills must be an array")
  }
  let mapped : Array[Json] = []
  for skill in skills {
    guard skill is Object(fields) else {
      fail("OpenAI local shell skill must be an object")
    }
    mapped.push({
      "name": openai_required_tool_string(
        fields, "name", "name", "local shell skill",
      ),
      "description": openai_required_tool_string(
        fields, "description", "description", "local shell skill",
      ),
      "path": openai_required_tool_string(
        fields, "path", "path", "local shell skill",
      ),
    })
  }
  Json::array(mapped)
}

///|
fn openai_shell_network_policy(value : Json) -> Json raise {
  guard value is Object(fields) else {
    fail("OpenAI shell networkPolicy must be an object")
  }
  let kind = openai_required_tool_string(
    fields, "type", "type", "shell networkPolicy",
  )
  match kind {
    "disabled" => ({ "type": "disabled" } : Json)
    "allowlist" => {
      guard openai_tool_field(fields, "allowedDomains", "allowed_domains")
        is Some(Array(allowed_domains)) else {
        fail("OpenAI shell allowlist requires allowedDomains")
      }
      let output : Map[String, Json] = Map([
        ("type", Json::string("allowlist")),
        ("allowed_domains", Json::array(allowed_domains)),
      ])
      match openai_tool_field(fields, "domainSecrets", "domain_secrets") {
        Some(Array(secrets)) =>
          output["domain_secrets"] = openai_tool_json_to_wire(
            Json::array(secrets),
          )
        Some(_) =>
          fail("OpenAI shell networkPolicy domainSecrets must be an array")
        None => ()
      }
      Json::object(output)
    }
    _ => fail("Unsupported OpenAI shell networkPolicy type '\{kind}'")
  }
}

///|
fn openai_shell_environment(value : Json) -> Json raise {
  guard value is Object(fields) else {
    fail("OpenAI shell environment must be an object")
  }
  let kind = openai_optional_tool_string(fields, "type", "type").unwrap_or(
    "local",
  )
  match kind {
    "containerReference" | "container_reference" =>
      (
        {
          "type": "container_reference",
          "container_id": openai_required_tool_string(
            fields, "containerId", "container_id", "shell containerReference",
          ),
        } : Json)
    "containerAuto" | "container_auto" => {
      let output : Map[String, Json] = Map([
        ("type", Json::string("container_auto")),
      ])
      match openai_tool_field(fields, "fileIds", "file_ids") {
        Some(Array(file_ids)) => output["file_ids"] = Json::array(file_ids)
        Some(_) => fail("OpenAI shell environment fileIds must be an array")
        None => ()
      }
      if openai_optional_tool_string(fields, "memoryLimit", "memory_limit")
        is Some(memory_limit) {
        guard memory_limit == "1g" ||
          memory_limit == "4g" ||
          memory_limit == "16g" ||
          memory_limit == "64g" else {
          fail("Unsupported OpenAI shell memoryLimit '\{memory_limit}'")
        }
        output["memory_limit"] = Json::string(memory_limit)
      }
      if openai_tool_field(fields, "networkPolicy", "network_policy")
        is Some(network_policy) {
        output["network_policy"] = openai_shell_network_policy(network_policy)
      }
      if openai_tool_field(fields, "skills", "skills") is Some(skills) {
        output["skills"] = openai_shell_skills(skills)
      }
      Json::object(output)
    }
    "local" => {
      let output : Map[String, Json] = Map([("type", Json::string("local"))])
      if openai_tool_field(fields, "skills", "skills") is Some(skills) {
        output["skills"] = openai_local_shell_skills(skills)
      }
      Json::object(output)
    }
    _ => fail("Unsupported OpenAI shell environment type '\{kind}'")
  }
}

///|
fn openai_shell_fields(args : Json) -> Map[String, Json] raise {
  let source = openai_raw_tool_fields(args, "openai.shell")
  let output : Map[String, Json] = Map([])
  if source.get("environment") is Some(environment) {
    output["environment"] = openai_shell_environment(environment)
  }
  output
}

///|
fn rename_openai_tool_field(
  fields : Map[String, Json],
  old_name : String,
  new_name : String,
) -> Map[String, Json] {
  let renamed : Map[String, Json] = Map([])
  for entry in fields.iter2() {
    let (key, value) = entry
    renamed[if key == old_name { new_name } else { key }] = value
  }
  renamed
}

///|
fn openai_provider_tool_type(id : String) -> String? {
  match id {
    "openai.file_search" => Some("file_search")
    "openai.local_shell" => Some("local_shell")
    "openai.shell" => Some("shell")
    "openai.apply_patch" => Some("apply_patch")
    "openai.computer" => Some("computer")
    "openai.web_search_preview" => Some("web_search_preview")
    "openai.web_search" => Some("web_search")
    "openai.code_interpreter" => Some("code_interpreter")
    "openai.image_generation" => Some("image_generation")
    "openai.mcp" => Some("mcp")
    "openai.custom" => Some("custom")
    "openai.programmatic_tool_calling" => Some("programmatic_tool_calling")
    "openai.tool_search" => Some("tool_search")
    _ => None
  }
}

///|
fn openai_provider_tool_names() -> Map[String, String] {
  Map([
    ("openai.code_interpreter", "code_interpreter"),
    ("openai.computer", "computer"),
    ("openai.file_search", "file_search"),
    ("openai.image_generation", "image_generation"),
    ("openai.local_shell", "local_shell"),
    ("openai.shell", "shell"),
    ("openai.web_search", "web_search"),
    ("openai.web_search_preview", "web_search_preview"),
    ("openai.mcp", "mcp"),
    ("openai.apply_patch", "apply_patch"),
    ("openai.tool_search", "tool_search"),
    ("openai.programmatic_tool_calling", "programmatic_tool_calling"),
  ])
}

///|
fn create_openai_v4_tool_name_mapping(
  tools : Array[@provider.LanguageModelV4Tool],
) -> @provider_utils.ToolNameMapping {
  @provider_utils.create_v4_tool_name_mapping(
    tools,
    openai_provider_tool_names(),
  )
}

///|
fn openai_function_tool(
  name : String,
  description : String?,
  input_schema : Json,
  strict : Bool?,
  provider_options : Map[String, Json],
) -> Json {
  let fields : Map[String, Json] = Map(
    [
      ("type", Json::string("function")),
      ("name", Json::string(name)),
      ..if description is Some(value) {
        [("description", Json::string(value))]
      },
      ("parameters", input_schema),
      ..if strict is Some(value) {
        [("strict", Json::boolean(value))]
      },
    ],
  )
  match provider_options.get("openai") {
    Some(Object(options)) => {
      match options.get("deferLoading") {
        Some(True) => fields["defer_loading"] = Json::boolean(true)
        Some(False) => fields["defer_loading"] = Json::boolean(false)
        _ => ()
      }
      match options.get("allowedCallers") {
        Some(Array(values)) => fields["allowed_callers"] = Json::array(values)
        _ => ()
      }
      if options.get("outputSchema") is Some(value) {
        fields["output_schema"] = value
      }
    }
    _ => ()
  }
  Json::object(fields)
}

///|
fn openai_function_tool_namespace(
  provider_options : Map[String, Json],
  warnings : Array[@provider.Warning],
) -> (String, String)? {
  guard provider_options.get("openai") is Some(Object(options)) else {
    return None
  }
  match options.get("namespace") {
    None => None
    Some({ "name": String(name), "description": String(description), .. }) =>
      Some((name, description))
    Some(_) => {
      warnings.push(
        @provider.Warning::Compatibility(
          feature="providerOptions.openai.namespace",
          details="Expected an object with string name and description fields; the invalid namespace was ignored.",
        ),
      )
      None
    }
  }
}

///|
fn openai_validate_string_array(value : Json, context : String) -> Unit raise {
  guard value is Array(values) else {
    fail("OpenAI \{context} must be an array of strings")
  }
  for item in values {
    guard item is String(_) else {
      fail("OpenAI \{context} must be an array of strings")
    }
  }
}

///|
fn openai_validate_mcp_args(args : Json) -> Unit raise {
  let fields = openai_raw_tool_fields(args, "openai.mcp")
  let server_label = openai_required_tool_string(
    fields, "serverLabel", "server_label", "MCP tool",
  )
  guard !server_label.trim().is_empty() else {
    fail("OpenAI MCP serverLabel must not be empty")
  }
  let server_url = openai_optional_tool_string(
    fields, "serverUrl", "server_url",
  )
  let connector_id = openai_optional_tool_string(
    fields, "connectorId", "connector_id",
  )
  guard server_url is Some(_) || connector_id is Some(_) else {
    fail("OpenAI MCP requires serverUrl or connectorId")
  }
  ignore(openai_optional_tool_string(fields, "authorization", "authorization"))
  ignore(
    openai_optional_tool_string(
      fields, "serverDescription", "server_description",
    ),
  )
  match openai_tool_field(fields, "allowedTools", "allowed_tools") {
    Some(Array(values)) =>
      openai_validate_string_array(Json::array(values), "MCP allowedTools")
    Some(Object(filter)) => {
      match openai_tool_field(filter, "readOnly", "read_only") {
        Some(True) | Some(False) | None => ()
        Some(_) => fail("OpenAI MCP allowedTools.readOnly must be a boolean")
      }
      if openai_tool_field(filter, "toolNames", "tool_names") is Some(value) {
        openai_validate_string_array(value, "MCP allowedTools.toolNames")
      }
    }
    Some(_) => fail("OpenAI MCP allowedTools must be an array or object")
    None => ()
  }
  match openai_tool_field(fields, "headers", "headers") {
    Some(Object(headers)) =>
      for entry in headers.iter2() {
        guard entry.1 is String(_) else {
          fail("OpenAI MCP header values must be strings")
        }
      }
    Some(_) => fail("OpenAI MCP headers must be an object of strings")
    None => ()
  }
  match openai_tool_field(fields, "requireApproval", "require_approval") {
    Some(String(value)) => {
      guard value == "always" || value == "never" else {
        fail(
          "OpenAI MCP requireApproval must be 'always', 'never', or an object",
        )
      }
    }
    Some(Object(approval)) =>
      match approval.get("never") {
        Some(Object(filter)) =>
          if openai_tool_field(filter, "toolNames", "tool_names") is Some(value) {
            openai_validate_string_array(
              value, "MCP requireApproval.never.toolNames",
            )
          }
        Some(_) => fail("OpenAI MCP requireApproval.never must be an object")
        None => ()
      }
    Some(_) =>
      fail("OpenAI MCP requireApproval must be 'always', 'never', or an object")
    None => ()
  }
}

///|
fn openai_mcp_fields(args : Json) -> Map[String, Json] raise {
  openai_validate_mcp_args(args)
  let source = openai_raw_tool_fields(args, "openai.mcp")
  let fields = openai_tool_fields(args, "openai.mcp")
  // Header names are protocol data, not schema field names.
  if openai_tool_field(source, "headers", "headers") is Some(headers) {
    fields["headers"] = headers
  }
  fields
}

///|
fn openai_tool_search_fields(args : Json) -> Map[String, Json] raise {
  let source = openai_raw_tool_fields(args, "openai.tool_search")
  match openai_tool_field(source, "execution", "execution") {
    Some(String("server" | "client")) | None => ()
    Some(_) => fail("OpenAI tool search execution must be 'server' or 'client'")
  }
  ignore(openai_optional_tool_string(source, "description", "description"))
  match openai_tool_field(source, "parameters", "parameters") {
    Some(Object(_)) | None => ()
    Some(_) => fail("OpenAI tool search parameters must be a JSON object")
  }
  let fields = openai_tool_fields(args, "openai.tool_search")
  // JSON Schema property names must remain byte-for-byte unchanged.
  if openai_tool_field(source, "parameters", "parameters") is Some(parameters) {
    fields["parameters"] = parameters
  }
  fields
}

///|
fn openai_provider_tool(
  id : String,
  name : String,
  args : Json,
  warnings : Array[@provider.Warning],
) -> Json? raise {
  let wire_type = match openai_provider_tool_type(id) {
    Some(value) => value
    None => {
      warnings.push(
        @provider.Warning::Unsupported(
          feature="provider tool \{id}",
          details="Unknown OpenAI provider tool was ignored.",
        ),
      )
      return None
    }
  }
  let mut fields = match id {
    "openai.code_interpreter" => openai_code_interpreter_fields(args)
    "openai.shell" => openai_shell_fields(args)
    "openai.mcp" => openai_mcp_fields(args)
    "openai.tool_search" => openai_tool_search_fields(args)
    _ => openai_tool_fields(args, id)
  }
  if id == "openai.file_search" {
    fields = rename_openai_tool_field(fields, "ranking", "ranking_options")
  }
  if id == "openai.mcp" && fields.get("require_approval") is None {
    fields["require_approval"] = Json::string("never")
  }
  let output : Map[String, Json] = Map(
    [
      ("type", Json::string(wire_type)),
      ..if id == "openai.custom" {
        [("name", Json::string(name))]
      },
    ],
  )
  for entry in fields.iter2() {
    let (key, value) = entry
    if key != "type" && !(id == "openai.custom" && key == "name") {
      output[key] = value
    }
  }
  Some(Json::object(output))
}

///|
fn prepare_openai_v4_responses_tools(
  tools : Array[@provider.LanguageModelV4Tool],
  warnings : Array[@provider.Warning],
) -> Array[Json] raise {
  let prepared : Array[Json] = []
  let namespace_output_indices : Map[String, Int] = Map([])
  let namespace_descriptions : Map[String, String] = Map([])
  let namespace_tools : Map[String, Array[Json]] = Map([])
  for tool in tools {
    match tool {
      @provider.V4FunctionTool(value) => {
        let function_tool = openai_function_tool(
          value.name,
          value.description,
          value.input_schema,
          value.strict,
          value.provider_options,
        )
        match openai_function_tool_namespace(value.provider_options, warnings) {
          None => prepared.push(function_tool)
          Some((namespace_name, namespace_description)) =>
            match namespace_output_indices.get(namespace_name) {
              Some(_) => {
                if namespace_descriptions.get(namespace_name) !=
                  Some(namespace_description) {
                  raise @provider.UnsupportedFunctionalityError(
                    functionality="conflicting descriptions for OpenAI tool namespace \"\{namespace_name}\"",
                  )
                }
                let grouped = namespace_tools[namespace_name].copy()
                grouped.push(function_tool)
                namespace_tools[namespace_name] = grouped
              }
              None => {
                namespace_output_indices[namespace_name] = prepared.length()
                namespace_descriptions[namespace_name] = namespace_description
                namespace_tools[namespace_name] = [function_tool]
                prepared.push(Json::null())
              }
            }
        }
      }
      @provider.V4ProviderTool(value) =>
        if openai_provider_tool(value.id, value.name, value.args, warnings)
          is Some(prepared_tool) {
          prepared.push(prepared_tool)
        }
    }
  }
  for entry in namespace_output_indices.iter2() {
    let (name, output_index) = entry
    prepared[output_index] = {
      "type": "namespace",
      "name": name,
      "description": namespace_descriptions[name],
      "tools": namespace_tools[name],
    }
  }
  prepared
}

///|
fn openai_v4_named_tool_choice(
  name : String,
  tools : Array[@provider.LanguageModelV4Tool],
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> Json {
  let resolved_name = tool_name_mapping.to_provider_tool_name(name)
  for tool in tools {
    match tool {
      @provider.V4ProviderTool(value) if value.id == "openai.custom" &&
        value.name == resolved_name =>
        return { "type": "custom", "name": resolved_name }
      _ => ()
    }
  }
  if resolved_name == "code_interpreter" ||
    resolved_name == "file_search" ||
    resolved_name == "image_generation" ||
    resolved_name == "web_search_preview" ||
    resolved_name == "web_search" ||
    resolved_name == "mcp" ||
    resolved_name == "apply_patch" ||
    resolved_name == "computer" ||
    resolved_name == "programmatic_tool_calling" {
    { "type": resolved_name }
  } else {
    { "type": "function", "name": resolved_name }
  }
}

///|
fn openai_v4_responses_tool_choice(
  choice : @provider.LanguageModelV4ToolChoice,
  tools : Array[@provider.LanguageModelV4Tool],
  tool_name_mapping : @provider_utils.ToolNameMapping,
) -> Json {
  match choice {
    @provider.V4ToolChoiceAuto => Json::string("auto")
    @provider.V4ToolChoiceNone => Json::string("none")
    @provider.V4ToolChoiceRequired => Json::string("required")
    @provider.V4ToolChoiceTool(name) =>
      openai_v4_named_tool_choice(name, tools, tool_name_mapping)
  }
}

///|
fn add_openai_programmatic_caller(
  provider_options : Map[String, Json],
) -> Map[String, Json] {
  let result = @provider.copy_provider_metadata(provider_options)
  let openai_options : Map[String, Json] = match result.get("openai") {
    Some(Object(fields)) => @provider.copy_provider_metadata(fields)
    _ => Map([])
  }
  let allowed_callers : Array[Json] = match
    openai_options.get("allowedCallers") {
    Some(Array(values)) => values.copy()
    _ => []
  }
  guard !allowed_callers.any(value => value == Json::string("programmatic")) else {
    return result
  }
  allowed_callers.push(Json::string("programmatic"))
  openai_options["allowedCallers"] = Json::array(allowed_callers)
  result["openai"] = Json::object(openai_options)
  result
}

///|
/// Create the high-level OpenAI programmatic caller tool.
///
/// When this tool is registered as a caller, each callee receives the
/// `openai.allowedCallers` option expected by the Responses API.
fn programmatic_tool_calling() -> @provider_utils.Tool {
  @provider_utils.experimental_tool_caller(
    @provider_utils.create_provider_executed_tool_factory(
      id="openai.programmatic_tool_calling",
      input_schema=openai_programmatic_tool_calling_input_schema(),
      output_schema=openai_programmatic_tool_calling_output_schema(),
      supports_deferred_results=true,
    ).create(),
    @provider_utils.ToolCallerDefinition::provider(
      add_openai_programmatic_caller,
    ),
  )
}
