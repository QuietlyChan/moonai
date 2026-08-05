///|
test "official OpenAI Responses maps options and system roles" {
  let options = @provider.ChatCallOptions::new(
    [
      @provider.LanguageModelMessage::system("Be concise"),
      @provider.LanguageModelMessage::user("hello"),
    ],
    response_format=@provider.ResponseFormat::json(
      name="answer",
      description="Structured answer",
      schema={ "type": "object" },
    ),
    temperature=0.4,
    top_p=0.8,
    provider_options={
      "openai": {
        "maxToolCalls": 3,
        "parallelToolCalls": false,
        "store": true,
        "strictJsonSchema": true,
        "textVerbosity": "low",
        "user": "user-1",
      },
    },
  )
  json_inspect(
    encode_openai_responses_request("gpt-4o", options, stream=false),
    content={
      "model": "gpt-4o",
      "input": [
        { "role": "system", "content": "Be concise" },
        {
          "role": "user",
          "content": [{ "type": "input_text", "text": "hello" }],
        },
      ],
      "temperature": 0.4,
      "top_p": 0.8,
      "text": {
        "format": {
          "type": "json_schema",
          "name": "answer",
          "schema": { "type": "object" },
          "strict": true,
          "description": "Structured answer",
        },
        "verbosity": "low",
      },
      "max_tool_calls": 3,
      "parallel_tool_calls": false,
      "store": true,
      "user": "user-1",
    },
  )
}

///|
test "official OpenAI Responses applies reasoning model compatibility" {
  let options = @provider.ChatCallOptions::new(
    [
      @provider.LanguageModelMessage::system("Think carefully"),
      @provider.LanguageModelMessage::user("hello"),
    ],
    reasoning_effort=@provider.High,
    temperature=0.7,
    top_p=0.9,
    provider_options={ "openai": { "store": false } },
  )
  json_inspect(encode_openai_responses_request("o1", options, stream=false), content={
    "model": "o1",
    "input": [
      { "role": "developer", "content": "Think carefully" },
      { "role": "user", "content": [{ "type": "input_text", "text": "hello" }] },
    ],
    "store": false,
    "include": ["reasoning.encrypted_content"],
    "reasoning": { "effort": "high", "summary": "detailed" },
  })
}

///|
test "OpenAI gpt-5.1 keeps sampling when reasoning is disabled" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("hello")],
    reasoning_effort=@provider.Disabled,
    temperature=0.5,
    top_p=0.3,
  )
  json_inspect(
    encode_openai_responses_request("gpt-5.1", options, stream=false),
    content={
      "model": "gpt-5.1",
      "input": [
        {
          "role": "user",
          "content": [{ "type": "input_text", "text": "hello" }],
        },
      ],
      "temperature": 0.5,
      "top_p": 0.3,
      "reasoning": { "effort": "none" },
    },
  )
}

///|
test "OpenAI Responses resolves wildcard media types and URL files" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_url(
        url="https://example.com/moon.png",
        media_type="image/*",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="iVBORw0KGgo=",
        media_type="image/*",
        filename="",
      ),
      @provider.LanguageModelContentPart::file_data(
        data="JVBERg==",
        media_type="application/*",
        filename="",
      ),
    ]),
  ])
  json_inspect(
    encode_openai_responses_request("gpt-4o", options, stream=false),
    content={
      "model": "gpt-4o",
      "input": [
        {
          "role": "user",
          "content": [
            {
              "type": "input_image",
              "image_url": "https://example.com/moon.png",
            },
            {
              "type": "input_image",
              "image_url": "data:image/png;base64,iVBORw0KGgo=",
            },
            {
              "type": "input_file",
              "filename": "part-2.pdf",
              "file_data": "data:application/pdf;base64,JVBERg==",
            },
          ],
        },
      ],
    },
  )
}

///|
test "OpenAI Responses resolves provider-reference files" {
  let reference = @provider.ProviderReference::new(
    Map([("openai", "file-openai"), ("anthropic", "file-anthropic")]),
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::file_reference(
        reference~,
        media_type="image/png",
      ),
      @provider.LanguageModelContentPart::file_reference(
        reference~,
        media_type="application/pdf",
      ),
    ]),
  ])
  json_inspect(
    encode_openai_responses_request("gpt-4o", options, stream=false),
    content={
      "model": "gpt-4o",
      "input": [
        {
          "role": "user",
          "content": [
            { "type": "input_image", "file_id": "file-openai" },
            { "type": "input_file", "file_id": "file-openai" },
          ],
        },
      ],
    },
  )
}

///|
test "official OpenAI Responses prepares function and provider tools" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("find the document")],
    tools=[
      @provider.ToolDefinition::new(
        "lookup",
        { "type": "object" },
        description="Look up a record",
        strict=true,
        provider_options={
          "openai": {
            "deferLoading": true,
            "allowedCallers": ["direct", "programmatic"],
            "outputSchema": { "type": "object" },
          },
        },
      ),
      file_search_tool(args={
        "vectorStoreIds": ["vs_1"],
        "maxNumResults": 5,
        "ranking": { "ranker": "auto", "scoreThreshold": 0.2 },
      }),
      web_search_tool(args={
        "searchContextSize": "high",
        "filters": { "allowedDomains": ["moonbitlang.com"] },
      }),
      code_interpreter_tool(),
      mcp_tool(args={ "serverLabel": "docs", "serverUrl": "https://mcp.test" }),
    ],
    tool_choice=@provider.Named("web_search"),
  )
  json_inspect(
    encode_openai_responses_request("gpt-5", options, stream=false),
    content={
      "model": "gpt-5",
      "input": [
        {
          "role": "user",
          "content": [{ "type": "input_text", "text": "find the document" }],
        },
      ],
      "include": [
        "web_search_call.action.sources", "code_interpreter_call.outputs",
      ],
      "tools": [
        {
          "type": "function",
          "name": "lookup",
          "description": "Look up a record",
          "parameters": { "type": "object" },
          "strict": true,
          "defer_loading": true,
          "allowed_callers": ["direct", "programmatic"],
          "output_schema": { "type": "object" },
        },
        {
          "type": "file_search",
          "vector_store_ids": ["vs_1"],
          "max_num_results": 5,
          "ranking_options": { "ranker": "auto", "score_threshold": 0.2 },
        },
        {
          "type": "web_search",
          "search_context_size": "high",
          "filters": { "allowed_domains": ["moonbitlang.com"] },
        },
        { "type": "code_interpreter", "container": { "type": "auto" } },
        {
          "type": "mcp",
          "server_label": "docs",
          "server_url": "https://mcp.test",
          "require_approval": "never",
        },
      ],
      "tool_choice": { "type": "web_search" },
    },
  )
}

///|
test "official OpenAI Responses encodes typed hosted-tool options" {
  let location = OpenAIWebSearchUserLocation::new(
    country="US",
    city="Seattle",
    region="Washington",
    timezone="America/Los_Angeles",
  )
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("use the hosted tools")],
    tools=[
      file_search_tool(
        args={ "vectorStoreIds": ["raw-value-must-not-win"] },
        options=OpenAIFileSearchOptions::new(
          vector_store_ids=["vs_docs"],
          max_num_results=8,
          ranking=OpenAIFileSearchRanking::new(
            ranker="auto",
            score_threshold=0.25,
          ),
          filters=OpenAIFileSearchFilter::all([
            OpenAIFileSearchFilter::comparison(
              key="category",
              operator=FileSearchEq,
              value=Json::string("docs"),
            ),
            OpenAIFileSearchFilter::comparison(
              key="tags",
              operator=FileSearchIn,
              value=Json::array([Json::string("moonbit"), Json::string("sdk")]),
            ),
          ]),
        ),
      ),
      web_search_preview_tool(
        options=OpenAIWebSearchPreviewOptions::new(
          search_context_size=WebSearchLow,
          user_location=location,
        ),
      ),
      web_search_tool(
        options=OpenAIWebSearchOptions::new(
          external_web_access=false,
          filters=OpenAIWebSearchFilters::new(
            allowed_domains=["moonbitlang.com"],
            blocked_domains=["example.com"],
          ),
          search_context_size=WebSearchHigh,
          user_location=location,
        ),
      ),
      image_generation_tool(
        options=OpenAIImageGenerationOptions::new(
          background=ImageBackgroundTransparent,
          input_fidelity=ImageFidelityHigh,
          input_image_mask=OpenAIImageGenerationMask::new(
            file_id="file-mask",
            image_url="data:image/png;base64,mask",
          ),
          model="gpt-image-1",
          moderation=ImageModerationAuto,
          output_compression=80,
          output_format=ImageFormatWebp,
          partial_images=2,
          quality=ImageQualityHigh,
          size=ImageSize1024x1536,
        ),
      ),
      mcp_tool(
        options=OpenAIMCPOptions::new(
          server_label="docs",
          allowed_tools=OpenAIMCPAllowedTools::filter(read_only=true, tool_names=[
            "search",
          ]),
          authorization="Bearer token",
          headers={ "X-Camel-Header": "preserved" },
          require_approval=OpenAIMCPApprovalPolicy::never_for(tool_names=[
            "delete",
          ]),
          server_description="Documentation server",
          server_url="https://mcp.example.test",
        ),
      ),
      custom_tool(
        "constrained_text",
        options=OpenAICustomToolOptions::new(
          description="Return a ticket ID",
          format=CustomGrammarFormat(
            syntax=CustomGrammarRegex,
            definition="TICKET-[0-9]+",
          ),
        ),
      ),
      tool_search_tool(
        options=OpenAIToolSearchOptions::new(
          execution=ToolSearchClient,
          description="Load tools by category",
          parameters={
            "type": "object",
            "properties": { "camelCaseInput": { "type": "string" } },
          },
        ),
      ),
    ],
  )
  json_inspect(
    encode_openai_responses_request("gpt-5", options, stream=false),
    content={
      "model": "gpt-5",
      "input": [
        {
          "role": "user",
          "content": [{ "type": "input_text", "text": "use the hosted tools" }],
        },
      ],
      "include": ["web_search_call.action.sources"],
      "tools": [
        {
          "type": "file_search",
          "vector_store_ids": ["vs_docs"],
          "max_num_results": 8,
          "ranking_options": { "ranker": "auto", "score_threshold": 0.25 },
          "filters": {
            "type": "and",
            "filters": [
              { "key": "category", "type": "eq", "value": "docs" },
              { "key": "tags", "type": "in", "value": ["moonbit", "sdk"] },
            ],
          },
        },
        {
          "type": "web_search_preview",
          "search_context_size": "low",
          "user_location": {
            "type": "approximate",
            "country": "US",
            "city": "Seattle",
            "region": "Washington",
            "timezone": "America/Los_Angeles",
          },
        },
        {
          "type": "web_search",
          "external_web_access": false,
          "filters": {
            "allowed_domains": ["moonbitlang.com"],
            "blocked_domains": ["example.com"],
          },
          "search_context_size": "high",
          "user_location": {
            "type": "approximate",
            "country": "US",
            "city": "Seattle",
            "region": "Washington",
            "timezone": "America/Los_Angeles",
          },
        },
        {
          "type": "image_generation",
          "background": "transparent",
          "input_fidelity": "high",
          "input_image_mask": {
            "file_id": "file-mask",
            "image_url": "data:image/png;base64,mask",
          },
          "model": "gpt-image-1",
          "moderation": "auto",
          "output_compression": 80,
          "output_format": "webp",
          "partial_images": 2,
          "quality": "high",
          "size": "1024x1536",
        },
        {
          "type": "mcp",
          "server_label": "docs",
          "allowed_tools": { "read_only": true, "tool_names": ["search"] },
          "authorization": "Bearer token",
          "headers": { "X-Camel-Header": "preserved" },
          "require_approval": { "never": { "tool_names": ["delete"] } },
          "server_description": "Documentation server",
          "server_url": "https://mcp.example.test",
        },
        {
          "type": "custom",
          "name": "constrained_text",
          "description": "Return a ticket ID",
          "format": {
            "type": "grammar",
            "syntax": "regex",
            "definition": "TICKET-[0-9]+",
          },
        },
        {
          "type": "tool_search",
          "execution": "client",
          "description": "Load tools by category",
          "parameters": {
            "type": "object",
            "properties": { "camelCaseInput": { "type": "string" } },
          },
        },
      ],
    },
  )
}

///|
test "typed image generation omits unset moderation" {
  json_inspect(
    OpenAIImageGenerationOptions::new().to_args_json(),
    content=Json::empty_object(),
  )
}

///|
test "official OpenAI Responses validates raw MCP arguments" {
  let invalid_args : Array[Json] = [
    { "serverUrl": "https://mcp.example.test" },
    { "serverLabel": "docs" },
    {
      "serverLabel": "docs",
      "serverUrl": "https://mcp.example.test",
      "headers": { "Authorization": 42 },
    },
  ]
  for args in invalid_args {
    let options = @provider.ChatCallOptions::new(
      [@provider.LanguageModelMessage::user("use MCP")],
      tools=[mcp_tool(args~)],
    )
    try encode_openai_responses_request("gpt-5", options, stream=false) catch {
      _ => ()
    } noraise {
      _ => fail("expected invalid raw MCP arguments to be rejected")
    }
  }
}

///|
test "official OpenAI Responses groups typed function tool namespaces" {
  let crm_namespace = OpenAIToolNamespace::new(
    name="crm",
    description="CRM tools for customer lookup and order management.",
  )
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("find a customer")],
    tools=[
      tool_search_tool(),
      @provider.ToolDefinition::new(
        "get_customer_profile",
        {
          "type": "object",
          "properties": { "customer_id": { "type": "string" } },
          "required": ["customer_id"],
        },
        description="Fetch a customer profile by customer ID.",
        provider_options=OpenAIToolOptions::new(
          allowed_callers=[Direct],
          tool_namespace=crm_namespace,
        ).to_provider_options(),
      ),
      @provider.ToolDefinition::new(
        "get_weather",
        { "type": "object" },
        description="Get the current weather.",
      ),
      @provider.ToolDefinition::new(
        "list_open_orders",
        { "type": "object" },
        description="List open orders for a customer ID.",
        strict=true,
        provider_options=OpenAIToolOptions::new(
          defer_loading=true,
          tool_namespace=crm_namespace,
        ).to_provider_options(),
      ),
    ],
  )
  json_inspect(
    encode_openai_responses_request("gpt-5", options, stream=false),
    content={
      "model": "gpt-5",
      "input": [
        {
          "role": "user",
          "content": [{ "type": "input_text", "text": "find a customer" }],
        },
      ],
      "tools": [
        { "type": "tool_search" },
        {
          "type": "namespace",
          "name": "crm",
          "description": "CRM tools for customer lookup and order management.",
          "tools": [
            {
              "type": "function",
              "name": "get_customer_profile",
              "description": "Fetch a customer profile by customer ID.",
              "parameters": {
                "type": "object",
                "properties": { "customer_id": { "type": "string" } },
                "required": ["customer_id"],
              },
              "allowed_callers": ["direct"],
            },
            {
              "type": "function",
              "name": "list_open_orders",
              "description": "List open orders for a customer ID.",
              "parameters": { "type": "object" },
              "strict": true,
              "defer_loading": true,
            },
          ],
        },
        {
          "type": "function",
          "name": "get_weather",
          "description": "Get the current weather.",
          "parameters": { "type": "object" },
        },
      ],
    },
  )
}

///|
test "official OpenAI Responses rejects conflicting tool namespace descriptions" {
  let first = OpenAIToolNamespace::new(name="crm", description="CRM tools.")
  let second = OpenAIToolNamespace::new(
    name="crm",
    description="Different CRM tools.",
  )
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("find a customer")],
    tools=[
      @provider.ToolDefinition::new(
        "get_customer_profile",
        { "type": "object" },
        provider_options=OpenAIToolOptions::new(tool_namespace=first).to_provider_options(),
      ),
      @provider.ToolDefinition::new(
        "list_open_orders",
        { "type": "object" },
        provider_options=OpenAIToolOptions::new(tool_namespace=second).to_provider_options(),
      ),
    ],
  )
  try encode_openai_responses_request("gpt-5", options, stream=false) catch {
    @provider.UnsupportedFunctionalityError(functionality~) =>
      assert_eq(
        functionality, "conflicting descriptions for OpenAI tool namespace \"crm\"",
      )
    error => fail("unexpected namespace error: \{error}")
  } noraise {
    _ => fail("expected conflicting OpenAI tool namespaces to be rejected")
  }
}

///|
test "official OpenAI Responses prepares code interpreter auto containers" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("analyze the files")],
    tools=[
      code_interpreter_tool(
        container=OpenAICodeInterpreterContainer::auto(file_ids=[
          "file-1", "file-2",
        ]),
      ),
    ],
  )
  json_inspect(
    encode_openai_responses_request("gpt-5", options, stream=false),
    content={
      "model": "gpt-5",
      "input": [
        {
          "role": "user",
          "content": [{ "type": "input_text", "text": "analyze the files" }],
        },
      ],
      "include": ["code_interpreter_call.outputs"],
      "tools": [
        {
          "type": "code_interpreter",
          "container": { "type": "auto", "file_ids": ["file-1", "file-2"] },
        },
      ],
    },
  )
}

///|
test "official OpenAI Responses maps shell container environments and skills" {
  let skill_reference = @provider.ProviderReference::single(
    provider="openai",
    id="skill_abc",
  )
  let network_policy = OpenAIShellNetworkPolicy::allowlist(
    ["moonbitlang.com"],
    domain_secrets=[
      OpenAIShellDomainSecret::new(
        domain="moonbitlang.com",
        name="TOKEN",
        value="secret",
      ),
    ],
  )
  let environment = OpenAIShellEnvironment::container_auto(
    file_ids=["file-1"],
    memory_limit=Memory16G,
    network_policy~,
    skills=[
      OpenAIShellSkill::reference(skill_reference),
      OpenAIShellSkill::inline(
        name="moonbit",
        description="MoonBit development skill",
        data="AAE=",
      ),
    ],
  )
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("inspect the repository")],
    tools=[shell_tool(environment~)],
    tool_choice=@provider.Named("shell"),
  )
  json_inspect(
    encode_openai_responses_request("gpt-5", options, stream=false),
    content={
      "model": "gpt-5",
      "input": [
        {
          "role": "user",
          "content": [
            { "type": "input_text", "text": "inspect the repository" },
          ],
        },
      ],
      "tools": [
        {
          "type": "shell",
          "environment": {
            "type": "container_auto",
            "file_ids": ["file-1"],
            "memory_limit": "16g",
            "network_policy": {
              "type": "allowlist",
              "allowed_domains": ["moonbitlang.com"],
              "domain_secrets": [
                {
                  "domain": "moonbitlang.com",
                  "name": "TOKEN",
                  "value": "secret",
                },
              ],
            },
            "skills": [
              {
                "type": "skill_reference",
                "skill_id": "skill_abc",
                "version": "latest",
              },
              {
                "type": "inline",
                "name": "moonbit",
                "description": "MoonBit development skill",
                "source": {
                  "type": "base64",
                  "media_type": "application/zip",
                  "data": "AAE=",
                },
              },
            ],
          },
        },
      ],
      "tool_choice": { "type": "function", "name": "shell" },
    },
  )
}

///|
test "official OpenAI Responses rejects unresolved shell skill references" {
  let skill_reference = @provider.ProviderReference::single(
    provider="anthropic",
    id="skill_abc",
  )
  let environment = OpenAIShellEnvironment::container_auto(skills=[
    OpenAIShellSkill::reference(skill_reference),
  ])
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("run the skill")],
    tools=[shell_tool(environment~)],
  )
  try encode_openai_responses_request("gpt-5", options, stream=false) catch {
    @provider.NoSuchProviderReferenceError(provider~, available_providers~) => {
      assert_eq(provider, "openai")
      assert_eq(available_providers, ["anthropic"])
    }
    error => fail("unexpected shell skill reference error: \{error}")
  } noraise {
    _ => fail("expected an unresolved OpenAI shell skill reference")
  }
}

///|
test "official OpenAI Responses omits an unspecified tool choice" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("find it")],
    tools=[
      @provider.ToolDefinition::new(
        "lookup",
        { "type": "object" },
        description="Look up a record",
      ),
    ],
  )
  json_inspect(
    encode_openai_responses_request("gpt-5", options, stream=false),
    content={
      "model": "gpt-5",
      "input": [
        {
          "role": "user",
          "content": [{ "type": "input_text", "text": "find it" }],
        },
      ],
      "tools": [
        {
          "type": "function",
          "name": "lookup",
          "description": "Look up a record",
          "parameters": { "type": "object" },
        },
      ],
    },
  )
}

///|
test "official OpenAI Responses maps prompt cache breakpoints and image detail" {
  let cached = @provider.LanguageModelContentPart::text("Hello").with_provider_options({
      "openai": { "promptCacheBreakpoint": { "mode": "explicit" } },
    },
  )
  let image = @provider.LanguageModelContentPart::image_data(
    data="AAECAw==",
    media_type="image/png",
  ).with_provider_options({ "openai": { "imageDetail": "high" } })
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::system("Rules", provider_options={
      "openai": { "promptCacheBreakpoint": { "mode": "explicit" } },
    }),
    @provider.LanguageModelMessage::user_parts([cached, image]),
  ])
  json_inspect(
    encode_openai_responses_request("gpt-4o", options, stream=false),
    content={
      "model": "gpt-4o",
      "input": [
        {
          "role": "system",
          "content": [
            {
              "type": "input_text",
              "text": "Rules",
              "prompt_cache_breakpoint": { "mode": "explicit" },
            },
          ],
        },
        {
          "role": "user",
          "content": [
            {
              "type": "input_text",
              "text": "Hello",
              "prompt_cache_breakpoint": { "mode": "explicit" },
            },
            {
              "type": "input_image",
              "image_url": "data:image/png;base64,AAECAw==",
              "detail": "high",
            },
          ],
        },
      ],
    },
  )
}

///|
test "official OpenAI Responses preserves assistant item metadata" {
  let assistant = @provider.LanguageModelContentPart::text("Earlier answer").with_provider_options({
      "openai": { "itemId": "msg_1", "phase": "commentary" },
    },
  )
  let call = @provider.ToolCall::new(
    id="call_1",
    name="lookup",
    arguments="{}",
    provider_metadata={ "openai": { "itemId": "fc_1", "namespace": "weather" } },
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant_parts([assistant], tool_calls=[
      call,
    ]),
  ])
  json_inspect(
    encode_openai_responses_request("gpt-4o", options, stream=false),
    content={
      "model": "gpt-4o",
      "input": [
        { "type": "item_reference", "id": "msg_1" },
        {
          "type": "function_call",
          "call_id": "call_1",
          "name": "lookup",
          "arguments": "{}",
          "namespace": "weather",
        },
      ],
    },
  )
}

///|
test "official OpenAI Responses encodes assistant tool-call content parts" {
  let call = @provider.ToolCall::new(
    id="call-part",
    name="lookup",
    arguments="{}",
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant_parts([
      @provider.LanguageModelContentPart::tool_call(call),
    ]),
  ])
  json_inspect(
    encode_openai_responses_request("gpt-4o", options, stream=false),
    content={
      "model": "gpt-4o",
      "input": [
        {
          "type": "function_call",
          "call_id": "call-part",
          "name": "lookup",
          "arguments": "{}",
        },
      ],
    },
  )
}

///|
test "official OpenAI Responses skips existing items after previous response" {
  let assistant = @provider.LanguageModelContentPart::text("Earlier answer").with_provider_options({
      "openai": { "itemId": "msg_1" },
    },
  )
  let call = @provider.ToolCall::new(
    id="call_1",
    name="lookup",
    arguments="{}",
    provider_metadata={ "openai": { "itemId": "fc_1" } },
  )
  let options = @provider.ChatCallOptions::new(
    [
      @provider.LanguageModelMessage::assistant_parts([assistant], tool_calls=[
        call,
      ]),
    ],
    provider_options={ "openai": { "previousResponseId": "resp_1" } },
  )
  json_inspect(
    encode_openai_responses_request("gpt-4o", options, stream=false),
    content={ "model": "gpt-4o", "input": [], "previous_response_id": "resp_1" },
  )
}

///|
test "official OpenAI Responses round trips encrypted reasoning input" {
  let options = @provider.ChatCallOptions::new(
    [
      @provider.LanguageModelMessage::assistant(
        "answer",
        reasoning_content="first thought",
        provider_options={
          "openai": {
            "itemId": "rs_1",
            "reasoningEncryptedContent": "encrypted-1",
            "store": false,
          },
        },
      ),
      @provider.LanguageModelMessage::assistant(
        "follow-up",
        reasoning_content="second thought",
        provider_options={
          "openai": {
            "itemId": "rs_1",
            "reasoningEncryptedContent": "encrypted-2",
          },
        },
      ),
    ],
    provider_options={ "openai": { "store": false } },
  )
  json_inspect(encode_openai_responses_request("o1", options, stream=false), content={
    "model": "o1",
    "input": [
      {
        "type": "reasoning",
        "id": "rs_1",
        "summary": [
          { "type": "summary_text", "text": "first thought" },
          { "type": "summary_text", "text": "second thought" },
        ],
        "encrypted_content": "encrypted-2",
      },
      {
        "role": "assistant",
        "content": [{ "type": "output_text", "text": "answer" }],
      },
      {
        "role": "assistant",
        "content": [{ "type": "output_text", "text": "follow-up" }],
      },
    ],
    "store": false,
    "include": ["reasoning.encrypted_content"],
  })
}

///|
test "official OpenAI Responses references stored reasoning items once" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant(
      "answer",
      reasoning_content="thinking",
      provider_options={ "openai": { "itemId": "rs_1" } },
    ),
    @provider.LanguageModelMessage::assistant(
      "next",
      reasoning_content="more thinking",
      provider_options={ "openai": { "itemId": "rs_1" } },
    ),
  ])
  json_inspect(encode_openai_responses_request("o1", options, stream=false), content={
    "model": "o1",
    "input": [
      { "type": "item_reference", "id": "rs_1" },
      {
        "role": "assistant",
        "content": [{ "type": "output_text", "text": "answer" }],
      },
      {
        "role": "assistant",
        "content": [{ "type": "output_text", "text": "next" }],
      },
    ],
  })
}

///|
test "official OpenAI Responses uses item references for provider-executed tool history" {
  let call = @provider.ToolCall::new(
    id="call_hosted",
    name="web_search",
    arguments="{}",
    provider_executed=true,
    provider_metadata={ "openai": { "itemId": "ws_1" } },
  )
  let result = @provider.LanguageModelMessage::tool(
    "call_hosted",
    "search result",
    provider_options={
      "openai": { "providerExecuted": true, "itemId": "ws_1" },
    },
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::assistant("", tool_calls=[call]),
    result,
  ])
  json_inspect(
    encode_openai_responses_request("gpt-4o", options, stream=false),
    content={
      "model": "gpt-4o",
      "input": [
        { "type": "item_reference", "id": "ws_1" },
        { "type": "item_reference", "id": "ws_1" },
      ],
    },
  )
}

///|
test "official OpenAI Responses keeps client tool results as function outputs" {
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::tool("call_client", "client result"),
  ])
  json_inspect(
    encode_openai_responses_request("gpt-4o", options, stream=false),
    content={
      "model": "gpt-4o",
      "input": [
        {
          "type": "function_call_output",
          "call_id": "call_client",
          "output": "client result",
        },
      ],
    },
  )
}

///|
test "official OpenAI Responses encodes structured results and approvals" {
  let result = @provider.LanguageModelToolResult::json(
    tool_call_id="call_client",
    tool_name="lookup",
    value={ "temperature": 18 },
  )
  let approval = @provider.LanguageModelToolApprovalResponse::new(
    approval_id="approval-1",
    approved=true,
  )
  let options = @provider.ChatCallOptions::new(
    [
      @provider.LanguageModelMessage::tool_content([
        @provider.LanguageModelContentPart::tool_result(result),
        @provider.LanguageModelContentPart::tool_approval_response(approval),
      ]),
    ],
    provider_options={ "openai": { "store": true } },
  )
  json_inspect(
    encode_openai_responses_request("gpt-4o", options, stream=false),
    content={
      "model": "gpt-4o",
      "input": [
        {
          "type": "function_call_output",
          "call_id": "call_client",
          "output": "{\"temperature\":18}",
        },
        { "type": "item_reference", "id": "approval-1" },
        {
          "type": "mcp_approval_response",
          "approval_request_id": "approval-1",
          "approve": true,
        },
      ],
      "store": true,
    },
  )
}

///|
test "OpenAI Responses maps custom provider-tool names in history and tool choice" {
  let tools = [code_interpreter_tool(name="sandbox")]
  let options = @provider.ChatCallOptions::new(
    [
      @provider.LanguageModelMessage::assistant("", tool_calls=[
        @provider.ToolCall::new(
          id="call_1",
          name="sandbox",
          arguments="{\"code\":\"1 + 1\"}",
        ),
      ]),
    ],
    tools~,
    tool_choice=@provider.Named("sandbox"),
  )
  json_inspect(
    encode_openai_responses_request("gpt-4o", options, stream=false),
    content={
      "model": "gpt-4o",
      "input": [
        {
          "type": "function_call",
          "call_id": "call_1",
          "name": "code_interpreter",
          "arguments": "{\"code\":\"1 + 1\"}",
        },
      ],
      "include": ["code_interpreter_call.outputs"],
      "tools": [{ "type": "code_interpreter", "container": { "type": "auto" } }],
      "tool_choice": { "type": "code_interpreter" },
    },
  )
}

///|
test "OpenAI Responses maps custom provider-tool names in allowedTools" {
  let options = @provider.ChatCallOptions::new(
    [@provider.LanguageModelMessage::user("run code")],
    tools=[code_interpreter_tool(name="sandbox")],
    provider_options={
      "openai": {
        "allowedTools": { "toolNames": ["sandbox"], "mode": "required" },
      },
    },
  )
  let body = encode_openai_responses_request("gpt-4o", options, stream=false)
  match body {
    {
      "tool_choice": {
        "type": "allowed_tools",
        "mode": "required",
        "tools": [{ "type": "function", "name": String(name), .. }],
        ..
      },
      ..
    } => assert_eq(name, "code_interpreter")
    _ => fail("expected mapped allowed_tools choice")
  }
}
