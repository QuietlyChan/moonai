///|
async test "streamText is provider-neutral and testable with a mock" {
  let usage : @moonai.Usage = {
    input_tokens: 2,
    output_tokens: 1,
    total_tokens: 3,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
  }
  let result : @moonai.ChatResponse = {
    text: "hello",
    reasoning: "",
    tool_calls: [],
    usage,
    finish_reason: @moonai.Stop,
  }
  let model = MockChatModel::new(
    [
      @moonai.StreamStart,
      @moonai.TextStart("text-0"),
      @moonai.TextDelta(id="text-0", delta="hello"),
      @moonai.TextEnd("text-0"),
      @moonai.Finish(usage~, reason=@moonai.Stop),
    ],
    result,
  )
  let deltas : Array[String] = []
  let actual = @moonai.streamText(model, prompt="say hello", on_event=event => {
    match event {
      @moonai.TextDelta(delta~, ..) => deltas.push(delta)
      _ => ()
    }
  })
  assert_eq(actual, result)
  assert_eq(deltas, ["hello"])
  assert_eq(model.captured_messages(), [@moonai.Message::user("say hello")])
}

///|
async test "generateText uses the same provider-neutral options" {
  let result : @moonai.ChatResponse = {
    text: "hello",
    reasoning: "",
    tool_calls: [],
    usage: @moonai.Usage::zero(),
    finish_reason: @moonai.Stop,
  }
  let model = MockChatModel::new([], result)
  let actual = @moonai.generateText(
    model,
    messages=[@moonai.Message::system("Be concise")],
    prompt="say hello",
  )
  assert_eq(actual, result)
  assert_eq(model.captured_messages(), [
    @moonai.Message::system("Be concise"),
    @moonai.Message::user("say hello"),
  ])
}

///|
async test "embedding helpers use a provider-neutral mock" {
  let result : @moonai.EmbeddingBatchResponse = {
    embeddings: [[0.1, 0.2], [0.3, 0.4]],
    usage: {
      input_tokens: 2,
      output_tokens: 0,
      total_tokens: 2,
      reasoning_tokens: 0,
      cached_input_tokens: 0,
    },
  }
  let model = MockEmbeddingModel::new(result)
  let actual = @moonai.embedMany(model, ["one", "two"])
  assert_eq(actual, result)
  assert_eq(model.captured_values(), ["one", "two"])
}

///|
async test "embedMany batches at the model limit and accumulates usage" {
  let result : @moonai.EmbeddingBatchResponse = {
    embeddings: [[0.1], [0.2]],
    usage: {
      input_tokens: 2,
      output_tokens: 0,
      total_tokens: 2,
      reasoning_tokens: 0,
      cached_input_tokens: 0,
    },
  }
  let model = MockEmbeddingModel::new(result, max_embeddings_per_call=2)
  let actual = @moonai.embedMany(model, ["one", "two", "three"])
  assert_eq(actual.embeddings, [[0.1], [0.2], [0.1]])
  assert_eq(actual.usage.input_tokens, 4)
  assert_eq(model.captured_batches(), [["one", "two"], ["three"]])
}

///|
async test "completion helpers use a provider-neutral mock" {
  let result : @moonai.CompletionResponse = {
    text: " complete",
    usage: @moonai.Usage::zero(),
    finish_reason: @moonai.Stop,
  }
  let model = MockCompletionModel::new(
    [@moonai.TextDelta(id="text-0", delta=" complete")],
    result,
  )
  let deltas : Array[String] = []
  let actual = @moonai.stream_completion(model, "MoonBit is", on_event=event => {
    match event {
      @moonai.TextDelta(delta~, ..) => deltas.push(delta)
      _ => ()
    }
  })
  assert_eq(actual, result)
  assert_eq(deltas, [" complete"])
  assert_eq(model.captured_prompt(), "MoonBit is")
}

///|
async test "generateImage batches through a provider-neutral mock" {
  let result : @moonai.ImageResponse = {
    images: [
      @moonai.GeneratedImage::new(@moonai.ImageData::Base64("mock-image")),
    ],
    usage: @moonai.Usage::zero(),
  }
  let model = MockImageModel::new(result, max_images_per_call=2)
  let actual = @moonai.generateImage(model, "MoonBit", n=3)
  assert_eq(actual.images.length(), 3)
  assert_eq(model.captured_batch_sizes(), [2, 1])
}

///|
async test "generateObject parses structured model output" {
  let result : @moonai.ChatResponse = {
    text: "{\"language\":\"MoonBit\",\"compiled\":true}",
    reasoning: "",
    tool_calls: [],
    usage: @moonai.Usage::zero(),
    finish_reason: @moonai.Stop,
  }
  let model = MockChatModel::new([], result)
  let actual = @moonai.generateObject(
    model,
    {
      "type": "object",
      "properties": {
        "language": { "type": "string" },
        "compiled": { "type": "boolean" },
      },
      "required": ["language", "compiled"],
    },
    prompt="Describe MoonBit",
    name="language_info",
  )
  json_inspect(actual.object, content={
    "language": "MoonBit",
    "compiled": true,
  })
  assert_eq(actual.response, result)
}
