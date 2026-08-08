///|
fn mock_chat_v4(model : MockChatModel) -> &@provider.LanguageModelV4 {
  @ai.as_language_model_v4(model as &@provider.ChatModel)
}

///|
async test "streamText is provider-neutral and testable with a mock" {
  let usage : @provider.Usage = {
    input_tokens: 2,
    output_tokens: 1,
    total_tokens: 3,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  }
  let result = @provider.ChatResponse::new(
    "hello",
    "",
    [],
    usage,
    @provider.Stop,
  )
  let model = MockChatModel::new(
    [
      @provider.StreamStart,
      @provider.TextStart("text-0"),
      @provider.TextDelta(id="text-0", delta="hello"),
      @provider.TextEnd("text-0"),
      @provider.Finish(usage~, reason=@provider.Stop),
    ],
    result,
  )
  let deltas : Array[String] = []
  let actual = @ai.streamText(mock_chat_v4(model), prompt="say hello", on_event=event => {
    match event {
      @provider.V4TextDelta(delta~, ..) => deltas.push(delta)
      _ => ()
    }
  })
  assert_eq(actual.finish_reason.unified, @provider.V4FinishStop)
  assert_eq(actual.usage.input_tokens.total, Some(2))
  assert_eq(actual.usage.output_tokens.total, Some(1))
  assert_eq(deltas, ["hello"])
  assert_eq(model.captured_messages(), [
    @provider.LanguageModelMessage::user("say hello"),
  ])
}

///|
async test "generateText uses the same provider-neutral options" {
  let result = @provider.ChatResponse::new(
    "hello",
    "",
    [],
    @provider.Usage::zero(),
    @provider.Stop,
  )
  let model = MockChatModel::new([], result)
  let actual = @ai.generateText(
    mock_chat_v4(model),
    messages=[@ai.ModelMessage::user("say hello")],
    instructions=@ai.Instructions::text("Be concise"),
  )
  assert_eq(actual.to_chat_response(), result)
  assert_eq(model.captured_messages(), [
    @provider.LanguageModelMessage::system("Be concise"),
    @provider.LanguageModelMessage::user("say hello"),
  ])
  assert_eq(model.captured_tool_choice(), None)
}

///|
async test "generateText rejects system messages unless explicitly enabled" {
  let model = MockChatModel::new([], @provider.ChatResponse::empty())
  try
    @ai.generateText(mock_chat_v4(model), messages=[
      @ai.ModelMessage::system("Be concise"),
      @ai.ModelMessage::user("say hello"),
    ])
  catch {
    @provider.InvalidPromptError(message~) =>
      assert_true(message.contains("system messages are not allowed"))
    error => fail("unexpected prompt error: \{error}")
  } noraise {
    _ => fail("expected system message validation to fail")
  }
  let _ = @ai.generateText(
    mock_chat_v4(model),
    messages=[
      @ai.ModelMessage::system("Be concise"),
      @ai.ModelMessage::user("say hello"),
    ],
    allow_system_in_messages=true,
  )
  assert_eq(model.captured_messages(), [
    @provider.LanguageModelMessage::system("Be concise"),
    @provider.LanguageModelMessage::user("say hello"),
  ])
}

///|
async test "generateText downloads URL assets unsupported by the model" {
  let result = @provider.ChatResponse::new(
    "ok",
    "",
    [],
    @provider.Usage::zero(),
    @provider.Stop,
  )
  let model = MockChatModel::new([], result)
  let captured_requests : Array[@ai.DownloadRequest] = []
  let custom_download : @ai.DownloadFunction = requests => {
    for request in requests {
      captured_requests.push(request)
    }
    [
      for request in requests => {
        if request.is_url_supported_by_model {
          None
        } else if request.url.has_suffix(".png") {
          Some(
            @ai.DownloadedAsset::new(
              data=@utf8.encode("PNG"),
              media_type="image/png",
            ),
          )
        } else {
          Some(
            @ai.DownloadedAsset::new(
              data=@utf8.encode("PDF"),
              media_type="application/pdf",
            ),
          )
        }
      }
    ]
  }
  let actual = @ai.generateText(
    mock_chat_v4(model),
    messages=[
      @ai.ModelMessage::user_parts([
        @ai.ModelContentPart::image_url("https://example.com/image.png"),
      ]),
      @ai.ModelMessage::tool_parts("call-1", [
        @ai.ModelContentPart::file_url(
          url="https://example.com/document.pdf",
          media_type="application/pdf",
          filename="document.pdf",
        ),
      ]),
    ],
    experimental_download=custom_download,
  )
  assert_eq(actual.to_chat_response(), result)
  assert_eq(captured_requests, [
    @ai.DownloadRequest::new(
      url="https://example.com/image.png",
      is_url_supported_by_model=false,
    ),
    @ai.DownloadRequest::new(
      url="https://example.com/document.pdf",
      is_url_supported_by_model=false,
    ),
  ])
  assert_eq(model.captured_messages(), [
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::image_data(
        data="UE5H",
        media_type="image/png",
      ),
    ]),
    @provider.LanguageModelMessage::tool_parts("call-1", [
      @provider.LanguageModelContentPart::tool_result(
        @provider.LanguageModelToolResult::content(
          tool_call_id="call-1",
          tool_name="",
          value=[
            @provider.LanguageModelToolFileData(
              data="UERG",
              media_type="application/pdf",
              filename="document.pdf",
              provider_options=Map([]),
            ),
          ],
        ),
      ),
    ]),
  ])
}

///|
async test "generateText passes model-supported URLs through" {
  let result = @provider.ChatResponse::new(
    "ok",
    "",
    [],
    @provider.Usage::zero(),
    @provider.Stop,
  )
  let model = MockChatModel::new([], result, supported_urls=[
    @provider.SupportedUrlRule::http("image/*"),
  ])
  let captured_requests : Array[@ai.DownloadRequest] = []
  let custom_download : @ai.DownloadFunction = requests => {
    for request in requests {
      captured_requests.push(request)
    }
    [
      for _request in requests => None
    ]
  }
  @ai.generateText(
    mock_chat_v4(model),
    messages=[
      @ai.ModelMessage::user_parts([
        @ai.ModelContentPart::image_url("HTTPS://EXAMPLE.COM/IMAGE.PNG"),
      ]),
    ],
    experimental_download=custom_download,
  )
  |> ignore
  assert_eq(captured_requests, [
    @ai.DownloadRequest::new(
      url="HTTPS://EXAMPLE.COM/IMAGE.PNG",
      is_url_supported_by_model=true,
    ),
  ])
  assert_eq(model.captured_messages(), [
    @provider.LanguageModelMessage::user_parts([
      @provider.LanguageModelContentPart::image_url(
        "HTTPS://EXAMPLE.COM/IMAGE.PNG",
      ),
    ]),
  ])
}

///|
async test "embedding helpers use a provider-neutral mock" {
  let result = @provider.EmbeddingBatchResponse::new([[0.1, 0.2], [0.3, 0.4]], {
    input_tokens: 2,
    output_tokens: 0,
    total_tokens: 2,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  })
  let model = MockEmbeddingModel::new(result)
  let actual = @ai.embedMany(model, ["one", "two"])
  assert_eq(actual, result)
  assert_eq(model.captured_values(), ["one", "two"])
}

///|
async test "embedMany batches at the model limit and accumulates usage" {
  let result = @provider.EmbeddingBatchResponse::new([[0.1], [0.2]], {
    input_tokens: 2,
    output_tokens: 0,
    total_tokens: 2,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  })
  let model = MockEmbeddingModel::new(result, max_embeddings_per_call=2)
  let actual = @ai.embedMany(model, ["one", "two", "three"])
  assert_eq(actual.embeddings, [[0.1], [0.2], [0.1]])
  assert_eq(actual.usage.input_tokens, 4)
  assert_eq(model.captured_batches(), [["one", "two"], ["three"]])
}

///|
async test "embedMany honors model parallel capability and caller limit" {
  let result = @provider.EmbeddingBatchResponse::new([[0.1]], {
    input_tokens: 1,
    output_tokens: 0,
    total_tokens: 1,
    reasoning_tokens: 0,
    cached_input_tokens: 0,
    cache_write_input_tokens: 0,
  })
  let model = MockEmbeddingModel::new(
    result,
    max_embeddings_per_call=1,
    supports_parallel_calls=true,
  )
  let actual = @ai.embed_many(
    model,
    ["one", "two", "three"],
    max_parallel_calls=2,
  )
  assert_eq(actual.embeddings, [[0.1], [0.1], [0.1]])
  assert_eq(actual.usage.input_tokens, 3)
  assert_eq(model.captured_batches(), [["one"], ["two"], ["three"]])
}

///|
async test "completion helpers use a provider-neutral mock" {
  let result = @provider.CompletionResponse::new(
    " complete",
    @provider.Usage::zero(),
    @provider.Stop,
  )
  let model = MockCompletionModel::new(
    [@provider.TextDelta(id="text-0", delta=" complete")],
    result,
  )
  let deltas : Array[String] = []
  let actual = @ai.stream_completion(model, "MoonBit is", on_event=event => {
    match event {
      @provider.TextDelta(delta~, ..) => deltas.push(delta)
      _ => ()
    }
  })
  assert_eq(actual, result)
  assert_eq(deltas, [" complete"])
  assert_eq(model.captured_prompt(), "MoonBit is")
}

///|
async test "generateImage batches through a provider-neutral mock" {
  let result = @provider.ImageResponse::new(
    [@provider.GeneratedImage::new(@provider.ImageData::Base64("mock-image"))],
    @provider.Usage::zero(),
  )
  let model = MockImageModel::new(result, max_images_per_call=2)
  let actual = @ai.generateImage(model, "MoonBit", n=3)
  assert_eq(actual.images.length(), 3)
  assert_eq(model.captured_batch_sizes(), [2, 1])
}

///|
async test "generateVideo uses the versioned provider contract and batches" {
  let result = @provider.VideoResponse::new([
    @provider.GeneratedVideo::new(
      @provider.GeneratedVideoData::Url("https://example.com/video.mp4"),
      "video/mp4",
    ),
  ])
  let model = MockVideoModel::new(result, max_videos_per_call=2)
  let actual = @ai.generateVideo(model, "MoonBit", n=3)
  assert_eq(actual.videos.length(), 3)
  assert_eq(model.captured_batch_sizes(), [2, 1])
  assert_true(
    actual.videos[0]
    is @provider.VideoV4Url(
      url="https://example.com/video.mp4",
      media_type="video/mp4"
    ),
  )
}

///|
async test "generateObject parses structured model output" {
  let result = @provider.ChatResponse::new(
    "{\"language\":\"MoonBit\",\"compiled\":true}",
    "",
    [],
    @provider.Usage::zero(),
    @provider.Stop,
  )
  let model = MockChatModel::new([], result)
  let actual = @ai.generateObject(
    mock_chat_v4(model),
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
  assert_eq(actual.response.to_chat_response(), result)
}

///|
async test "generateObject rejects output that does not match its schema" {
  let result = @provider.ChatResponse::new(
    "{\"language\":42}",
    "",
    [],
    @provider.Usage::zero(),
    @provider.Stop,
  )
  let model = MockChatModel::new([], result)
  try
    @ai.generateObject(
      mock_chat_v4(model),
      {
        "type": "object",
        "properties": { "language": { "type": "string" } },
        "required": ["language"],
      },
      prompt="Describe MoonBit",
    )
  catch {
    @ai.NoObjectGeneratedError(message~, text~, response~, failure~) => {
      assert_eq(message, "No object generated: response did not match schema.")
      assert_eq(text, Some("{\"language\":42}"))
      assert_eq(response.to_chat_response(), result)
      assert_eq(
        failure,
        @ai.SchemaMismatch(
          path="$.language",
          message="value has the wrong JSON type",
        ),
      )
    }
    error => fail("unexpected structured output error: \{error}")
  } noraise {
    _ => fail("expected schema validation to fail")
  }
}

///|
async test "generateObject reports invalid JSON separately" {
  let result = @provider.ChatResponse::new(
    "not-json",
    "",
    [],
    @provider.Usage::zero(),
    @provider.Stop,
  )
  let model = MockChatModel::new([], result)
  try
    @ai.generateObject(
      mock_chat_v4(model),
      { "type": "object" },
      prompt="Describe MoonBit",
    )
  catch {
    @ai.NoObjectGeneratedError(text~, failure~, ..) => {
      assert_eq(text, Some("not-json"))
      assert_true(failure is @ai.InvalidJson(_))
    }
    error => fail("unexpected structured output error: \{error}")
  } noraise {
    _ => fail("expected JSON parsing to fail")
  }
}

///|
async test "rerank reconstructs provider ordering and forwards options" {
  let result = @provider.RerankingModelV4Result::new([
    @provider.RerankingModelV4Ranking::new(2, 0.95),
    @provider.RerankingModelV4Ranking::new(0, 0.75),
  ])
  let model = MockRerankingModelV4::new(result)
  let actual = @ai.rerankText(
    model,
    ["first", "second", "third"],
    "which is best?",
    top_n=2,
    headers=Map([("x-test", "yes")]),
    provider_options=Map([("mock", { "mode": "fast" })]),
  )
  assert_eq(actual.ranking.length(), 2)
  assert_eq(actual.ranking[0].original_index, 2)
  assert_eq(actual.ranking[0].score, 0.95)
  assert_eq(
    actual.ranking[0].document,
    @ai.RerankingDocument::TextDocument("third"),
  )
  assert_eq(actual.ranking[1].original_index, 0)
  assert_eq(actual.ranking[1].score, 0.75)
  assert_eq(
    actual.ranking[1].document,
    @ai.RerankingDocument::TextDocument("first"),
  )
  match actual.reranked_documents {
    @provider.TextDocuments(values) => assert_eq(values, ["third", "first"])
    @provider.ObjectDocuments(_) => fail("expected text documents")
  }
  match model.captured_options() {
    Some(options) => {
      assert_eq(options.query, "which is best?")
      assert_eq(options.top_n, Some(2))
      assert_eq(options.headers, Map([("x-test", "yes")]))
    }
    None => fail("expected reranking model to be called")
  }
}

///|
async test "rerank preserves object document representation" {
  let result = @provider.RerankingModelV4Result::new([
    @provider.RerankingModelV4Ranking::new(1, 0.8),
  ])
  let model = MockRerankingModelV4::new(result)
  let actual = @ai.rerank(
    model,
    @provider.RerankingModelV4Documents::objects([{ "id": 1 }, { "id": 2 }]),
    "query",
  )
  match actual.reranked_documents {
    @provider.ObjectDocuments(values) => assert_eq(values, [{ "id": 2 }])
    @provider.TextDocuments(_) => fail("expected object documents")
  }
}

///|
async test "rerank returns an empty result without invoking the model" {
  let result = @provider.RerankingModelV4Result::new([
    @provider.RerankingModelV4Ranking::new(0, 1.0),
  ])
  let model = MockRerankingModelV4::new(result)
  let actual = @ai.rerankText(model, [], "query")
  match actual.reranked_documents {
    @provider.TextDocuments(values) => assert_eq(values, [])
    @provider.ObjectDocuments(_) => fail("expected text documents")
  }
  match model.captured_options() {
    Some(_) => fail("empty reranking must not invoke the model")
    None => ()
  }
}

///|
async test "rerank rejects invalid provider indices" {
  let result = @provider.RerankingModelV4Result::new([
    @provider.RerankingModelV4Ranking::new(4, 1.0),
  ])
  let model = MockRerankingModelV4::new(result)
  try @ai.rerankText(model, ["one"], "query") catch {
    @provider.InvalidResponseDataError(message~, data~) => {
      assert_true(message.contains("out-of-range"))
      json_inspect(data, content={ "index": 4 })
    }
    error => fail("unexpected reranking error: \{error}")
  } noraise {
    _ => fail("expected invalid reranking response")
  }
}

///|
async test "standard helpers honor cancellation before invoking a model" {
  let token = @provider.CancellationToken::new()
  token.cancel()
  let model = MockChatModel::new(
    [],
    @provider.ChatResponse::new(
      "ignored",
      "",
      [],
      @provider.Usage::zero(),
      @provider.Stop,
    ),
  )
  try
    @ai.generateText(
      mock_chat_v4(model),
      prompt="cancelled",
      cancellation_token=token,
    )
  catch {
    @provider.CancellationError => ()
    error => fail("unexpected cancellation error: \{error}")
  } noraise {
    _ => fail("expected cancellation")
  }
}

///|
async test "streamTranscribe uses the provider-neutral audio stream contract" {
  let result = @provider.TranscriptionResponse::new(
    text="hello world",
    language="en",
  )
  let configured_events : Array[@provider.TranscriptionStreamEvent] = [
    @provider.TranscriptionStreamStart(warnings=[]),
    @provider.TranscriptionDelta(
      id=Some("segment-1"),
      delta="hello ",
      provider_metadata=Map([]),
    ),
    @provider.TranscriptionFinal(
      id=Some("segment-1"),
      text="hello world",
      start_second=None,
      end_second=None,
      channel_index=None,
      provider_metadata=Map([]),
    ),
    @provider.TranscriptionFinish(
      text="hello world",
      segments=[],
      language=Some("en"),
      duration_seconds=None,
      provider_metadata=Map([]),
    ),
  ]
  let model = MockTranscriptionModel::new(
    result,
    stream_events=configured_events,
  )
  let audio = @provider.audio_chunks([@provider.AudioChunk::base64("AQID")])
  let observed : Array[@provider.TranscriptionStreamEvent] = []
  let actual = @ai.experimental_streamTranscribe(
    model,
    audio~,
    input_audio_format=@provider.AudioFormat::new(
      media_type="audio/pcm",
      sample_rate=24_000,
    ),
    on_event=event => observed.push(event),
  )
  assert_eq(actual, result)
  assert_eq(observed, configured_events)
  match model.captured_stream_options() {
    Some(options) => {
      assert_eq(options.input_audio_format.media_type, "audio/pcm")
      assert_eq(options.input_audio_format.sample_rate, Some(24_000))
    }
    None => fail("expected the streaming transcription model to be called")
  }
}
