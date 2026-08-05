///|
fn middleware_add_marker(
  options : @provider.ChatCallOptions,
) -> @provider.ChatCallOptions {
  let provider_options = @provider.copy_provider_metadata(
    options.provider_options,
  )
  provider_options["middleware"] = { "applied": true }
  @provider.ChatCallOptions::new(
    options.messages,
    tools=options.tools,
    tool_choice?=options.tool_choice,
    response_format=options.response_format,
    reasoning_effort=options.reasoning_effort,
    max_output_tokens?=options.max_output_tokens,
    temperature?=options.temperature,
    top_p?=options.top_p,
    top_k?=options.top_k,
    frequency_penalty?=options.frequency_penalty,
    presence_penalty?=options.presence_penalty,
    seed?=options.seed,
    stop_sequences=options.stop_sequences,
    include_raw_chunks=options.include_raw_chunks,
    headers=options.headers,
    provider_options~,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}

///|
async test "chat model middleware transforms options and overrides identity" {
  let base = @testing.MockChatModel::new(
    [],
    @provider.ChatResponse::new(
      "ok",
      "",
      [],
      @provider.Usage::zero(),
      @provider.Stop,
    ),
    provider_name="base",
    model_id="base-model",
    supported_urls=[@provider.SupportedUrlRule::new("image/*", ["base"])],
  )
  let wrapped = wrap_chat_model(
    base,
    ChatModelMiddleware::new(
      transform_options=middleware_add_marker,
      provider="middleware",
      model_id="derived-model",
      supported_urls=[@provider.SupportedUrlRule::new("image/*", ["derived"])],
    ),
  )
  let options = @provider.ChatCallOptions::new([
    @provider.LanguageModelMessage::user("hello"),
  ])
  ignore(wrapped.generate(options))
  assert_eq(wrapped.provider(), "middleware")
  assert_eq(wrapped.model_id(), "derived-model")
  assert_eq(wrapped.supported_urls().length(), 1)
  assert_eq(wrapped.supported_urls()[0].url_patterns()[0], "derived")
  let captured = base.captured_messages()
  assert_eq(captured.length(), 1)
}

///|
async test "chat model middleware applies the same transform to streaming" {
  let base = @testing.MockChatModel::new(
    [@provider.TextDelta(id="text-0", delta="ok")],
    @provider.ChatResponse::new(
      "ok",
      "",
      [],
      @provider.Usage::zero(),
      @provider.Stop,
    ),
  )
  let wrapped = wrap_chat_model(
    base,
    ChatModelMiddleware::new(transform_options=middleware_add_marker),
  )
  let mut events = 0
  ignore(
    wrapped.stream(
      @provider.ChatCallOptions::new([
        @provider.LanguageModelMessage::user("hello"),
      ]),
      _ => events = events + 1,
    ),
  )
  assert_eq(events, 1)
  assert_eq(base.captured_messages().length(), 1)
}

///|
async test "image model middleware overrides identity and limits" {
  let base = @testing.MockImageModel::new(
    @provider.ImageResponse::new(
      [@provider.GeneratedImage::new(@provider.Base64("image"))],
      @provider.Usage::zero(),
    ),
    max_images_per_call=2,
    provider_name="base-image",
    model_id="base-image-model",
  )
  let wrapped = wrap_image_wire_model(
    base,
    ImageWireModelMiddleware::new(
      provider="middleware-image",
      model_id="derived-image-model",
      max_images_per_call=4,
    ),
  )
  assert_eq(wrapped.provider(), "middleware-image")
  assert_eq(wrapped.model_id(), "derived-image-model")
  assert_eq(wrapped.max_images_per_call(), 4)
  ignore(wrapped.generate(@provider.ImageCallOptions::new("hello", n=1)))
  assert_eq(base.captured_batch_sizes(), [1])
}

///|
async fn async_chat_transform(
  context : ChatModelTransformContext,
) -> @provider.ChatCallOptions {
  @async.pause()
  let options = context.params
  @provider.ChatCallOptions::new(
    options.messages,
    tools=options.tools,
    tool_choice?=options.tool_choice,
    response_format=options.response_format,
    reasoning_effort=options.reasoning_effort,
    max_output_tokens?=options.max_output_tokens,
    temperature=0.75,
    top_p?=options.top_p,
    top_k?=options.top_k,
    frequency_penalty?=options.frequency_penalty,
    presence_penalty?=options.presence_penalty,
    seed?=options.seed,
    stop_sequences=options.stop_sequences,
    include_raw_chunks=options.include_raw_chunks,
    headers=options.headers,
    provider_options=options.provider_options,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}

///|
async fn wrapped_chat_result(
  _context : ChatModelMiddlewareContext,
) -> @provider.ChatResponse {
  @async.pause()
  @provider.ChatResponse::new(
    "wrapped",
    "",
    [],
    @provider.Usage::zero(),
    @provider.Stop,
  )
}

///|
async test "chat middleware chains transforms in declaration order and wraps results" {
  let base = @testing.MockChatModel::new(
    [],
    @provider.ChatResponse::new(
      "base",
      "",
      [],
      @provider.Usage::zero(),
      @provider.Stop,
    ),
  )
  let wrapped = wrap_chat_model_chain(base, [
    ChatModelMiddleware::new(transform_params=async_chat_transform),
    ChatModelMiddleware::new(wrap_generate=wrapped_chat_result),
  ])
  let result = wrapped.generate(
    @provider.ChatCallOptions::new([
      @provider.LanguageModelMessage::user("hello"),
    ]),
  )
  assert_eq(result.text, "wrapped")
}

///|
async fn passthrough_chat_stream(
  context : ChatModelMiddlewareContext,
) -> @provider.ChatResponse {
  context.stream()
}

///|
async test "chat middleware stream wrapper delegates to the inner stream" {
  let base = @testing.MockChatModel::new(
    [@provider.TextDelta(id="text-0", delta="ok")],
    @provider.ChatResponse::new(
      "ok",
      "",
      [],
      @provider.Usage::zero(),
      @provider.Stop,
    ),
  )
  let mut events = 0
  let wrapped = wrap_chat_model(
    base,
    ChatModelMiddleware::new(wrap_stream=passthrough_chat_stream),
  )
  ignore(
    wrapped.stream(
      @provider.ChatCallOptions::new([
        @provider.LanguageModelMessage::user("hello"),
      ]),
      _ => events = events + 1,
    ),
  )
  assert_eq(events, 1)
}

///|
async fn async_image_transform(
  options : @provider.ImageCallOptions,
  _model : &@provider.ImageWireModel,
) -> @provider.ImageCallOptions {
  @async.pause()
  @provider.ImageCallOptions::new(
    options.prompt,
    n=2,
    size?=options.size,
    aspect_ratio?=options.aspect_ratio,
    seed?=options.seed,
    files=options.files,
    mask?=options.mask,
    headers=options.headers,
    provider_options=options.provider_options,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}

///|
async fn passthrough_image_result(
  context : ImageWireModelMiddlewareContext,
) -> @provider.ImageResponse {
  context.generate()
}

///|
async test "image middleware chains async transforms and wraps generation" {
  let base = @testing.MockImageModel::new(
    @provider.ImageResponse::new(
      [@provider.GeneratedImage::new(@provider.Base64("image"))],
      @provider.Usage::zero(),
    ),
  )
  let wrapped = wrap_image_wire_model_chain(base, [
    ImageWireModelMiddleware::new(transform_params=async_image_transform),
    ImageWireModelMiddleware::new(wrap_generate=passthrough_image_result),
  ])
  ignore(wrapped.generate(@provider.ImageCallOptions::new("hello", n=1)))
  assert_eq(base.captured_batch_sizes(), [2])
}
