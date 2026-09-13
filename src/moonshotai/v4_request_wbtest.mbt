///|
fn moonshot_test_options(
  prompt~ : Array[@provider.LanguageModelV4Message],
  provider_options? : Map[String, Json] = Map([]),
  max_output_tokens? : Int,
  tools? : Array[@provider.LanguageModelV4Tool],
  tool_choice? : @provider.LanguageModelV4ToolChoice,
  reasoning? : @provider.LanguageModelV4ReasoningEffort,
) -> @provider.LanguageModelV4CallOptions {
  @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new(prompt),
    provider_options~,
    max_output_tokens?,
    tools?,
    tool_choice?,
    reasoning?,
  )
}

///|
fn moonshot_prepare(
  model_id~ : String,
  options~ : @provider.LanguageModelV4CallOptions,
) -> PreparedMoonshotRequest raise {
  prepare_moonshot_v4_request(
    model_id,
    options,
    "moonshotai.chat",
    false,
    true,
    get_model_structured_output_support(model_id),
  )
}

///|
test "Moonshot sends max_completion_tokens natively (#19605)" {
  let prepared = moonshot_prepare(
    model_id="kimi-k2.5",
    options=moonshot_test_options(
      prompt=[
        @provider.V4UserMessage(
          content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
          provider_options=Map([]),
        ),
      ],
      max_output_tokens=512,
    ),
  )
  assert_true(
    prepared.body.stringify().contains("\"max_completion_tokens\":512"),
  )
  assert_true(!prepared.body.stringify().contains("\"max_tokens\""))
}

///|
test "Moonshot omits required tool choice on K2.6+ (#19633)" {
  let schema : Json = { "type": "object", "properties": {} }
  let tools = [@provider.LanguageModelV4Tool::function("lookup", schema)]
  // kimi-k2.6 rejects required tool choice; the setting is dropped with a
  // warning.
  let prepared = moonshot_prepare(
    model_id="kimi-k2.6",
    options=moonshot_test_options(
      prompt=[
        @provider.V4UserMessage(
          content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
          provider_options=Map([]),
        ),
      ],
      tools~,
      tool_choice=@provider.V4ToolChoiceRequired,
    ),
  )
  let body = prepared.body.stringify()
  assert_true(!body.contains("\"tool_choice\""))
  assert_true(
    prepared.warnings.any(warning => {
      warning
      is @provider.Unsupported(
        feature="tool choice \"required\" for model \"kimi-k2.6\"",
        ..
      )
    }),
  )
  // Other models keep the setting.
  let allowed = moonshot_prepare(
    model_id="kimi-k2.5",
    options=moonshot_test_options(
      prompt=[
        @provider.V4UserMessage(
          content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
          provider_options=Map([]),
        ),
      ],
      tools~,
      tool_choice=@provider.V4ToolChoiceRequired,
    ),
  )
  assert_eq(
    allowed.body.stringify().contains("\"tool_choice\":\"required\""),
    true,
  )
}

///|
test "Moonshot structured outputs accept moonshot-v1 schemas (#19583)" {
  let options = @provider.LanguageModelV4CallOptions::new(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
        provider_options=Map([]),
      ),
    ]),
    response_format=@provider.LanguageModelV4ResponseFormat::json(
      name="answer",
      schema={ "type": "object", "properties": { "ok": { "type": "boolean" } } },
    ),
    provider_options={ "moonshotai": { "strictJsonSchema": false } },
  )
  let with_schema = moonshot_prepare(model_id="moonshot-v1-128k", options~)
  let body = with_schema.body.stringify()
  assert_true(body.contains("\"type\":\"json_schema\""))
  assert_true(body.contains("\"strict\":false"))
  assert_true(!body.contains("$schema"))
}

///|
test "Moonshot Kimi models suppress fixed sampling options" {
  let prepared = moonshot_prepare(
    model_id="kimi-k2.5",
    options=@provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4UserMessage(
          content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
          provider_options=Map([]),
        ),
      ]),
      temperature=0.7,
      top_p=0.9,
    ),
  )
  let body = prepared.body.stringify()
  assert_true(!body.contains("temperature"))
  assert_true(!body.contains("top_p"))
  assert_eq(prepared.warnings.length(), 2)
}

///|
test "Moonshot K3 maps reasoning levels and drops thinking" {
  let prepared = moonshot_prepare(
    model_id="kimi-k3",
    options=@provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4UserMessage(
          content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
          provider_options=Map([]),
        ),
      ]),
      reasoning=@provider.V4ReasoningMedium,
      provider_options={ "moonshotai": { "thinking": { "type": "disabled" } } },
    ),
  )
  let body = prepared.body.stringify()
  assert_true(!body.contains("\"thinking\""))
  assert_true(body.contains("\"reasoning_effort\":\"high\""))
  assert_true(
    prepared.warnings.any(warning => {
      warning is @provider.Unsupported(feature="thinking", ..)
    }),
  )
}

///|
test "Moonshot K2.6 preserved reasoning keeps all thinking output" {
  let prepared = moonshot_prepare(
    model_id="kimi-k2.6",
    options=moonshot_test_options(
      prompt=[
        @provider.V4UserMessage(
          content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
          provider_options=Map([]),
        ),
      ],
      provider_options={ "moonshotai": { "reasoningHistory": "preserved" } },
    ),
  )
  let body = prepared.body.stringify()
  assert_true(
    body.contains("\"thinking\":{\"type\":\"enabled\",\"keep\":\"all\"}"),
  )
}

///|
test "Moonshot K3 accepts dynamic tools on empty system messages" {
  let prepared = moonshot_prepare(
    model_id="kimi-k3",
    options=@provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4SystemMessage(content="", provider_options={
          "moonshotai": {
            "tools": [
              {
                "type": "function",
                "name": "weather",
                "inputSchema": { "type": "object", "properties": {} },
              },
            ],
          },
        }),
        @provider.V4UserMessage(
          content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
          provider_options=Map([]),
        ),
      ]),
    ),
  )
  let body = prepared.body.stringify()
  assert_true(body.contains("\"tools\":[{\"type\":\"function\""))
  assert_true(body.contains("\"name\":\"weather\""))
}

///|
test "Moonshot assistant partial mode flows through to the wire" {
  let prepared = moonshot_prepare(
    model_id="kimi-k2.5",
    options=@provider.LanguageModelV4CallOptions::new(
      @provider.LanguageModelV4Prompt::new([
        @provider.V4UserMessage(
          content=[@provider.V4PromptText(text="hi", provider_options=Map([]))],
          provider_options=Map([]),
        ),
        @provider.V4AssistantMessage(
          content=[
            @provider.V4PromptText(
              text="The answer is",
              provider_options=Map([]),
            ),
          ],
          provider_options={ "moonshotai": { "partial": true } },
        ),
      ]),
    ),
  )
  let body = prepared.body.stringify()
  assert_true(body.contains("\"partial\":true"))
}

///|
test "Moonshot MFJS turns tuple items into prefixItems" {
  let normalized = normalize_json_schema_for_mfjs({
    "type": "object",
    "properties": {
      "pair": {
        "type": "array",
        "items": [{ "type": "string" }, { "type": "number" }],
      },
    },
  })
  let text = normalized.stringify()
  assert_true(text.contains("\"prefixItems\""))
  assert_true(!text.contains("\"items\":[{\"type\":\"string\"}"))
}

///|
test "Moonshot MFJS requires an object root" {
  let outcome = try {
    let _ = normalize_json_schema_for_mfjs({ "type": "string" })
    None
  } catch {
    error => Some(error)
  }
  assert_true(outcome is Some(@provider.UnsupportedFunctionalityError(_)))
}

///|
test "Moonshot prompt conversion renders ms:// references and video parts" {
  let conversion = convert_v4_prompt_to_moonshot(
    @provider.LanguageModelV4Prompt::new([
      @provider.V4UserMessage(
        content=[
          @provider.V4PromptText(text="compare", provider_options=Map([])),
          @provider.V4PromptFile(
            data=@provider.V4FileReference(
              @provider.ProviderReference::single(
                provider="moonshotai",
                id="ms://files/abc",
              ),
            ),
            media_type="image/png",
            filename=None,
            provider_options=Map([]),
          ),
          @provider.V4PromptFile(
            data=@provider.V4FileUrl("https://example.test/clip.mp4"),
            media_type="video/mp4",
            filename=None,
            provider_options=Map([]),
          ),
        ],
        provider_options=Map([]),
      ),
    ]),
    model_id="moonshot-v1-128k-vision-preview",
    provider_name="moonshotai.chat",
    response_format=None,
  )
  let body = Json::array(conversion.messages).stringify()
  assert_true(body.contains("\"type\":\"image_url\""))
  assert_true(body.contains("\"url\":\"ms://files/abc\""))
  assert_true(body.contains("\"type\":\"video_url\""))
}
