///|
test "Alibaba typed chat options match the provider namespace" {
  json_inspect(
    AlibabaLanguageModelChatOptions::new(
      enable_thinking=true,
      thinking_budget=2048,
      parallel_tool_calls=false,
    ).to_provider_options(),
    content={
      "alibaba": {
        "enableThinking": true,
        "thinkingBudget": 2048,
        "parallelToolCalls": false,
      },
    },
  )
  try AlibabaLanguageModelChatOptions::new(thinking_budget=0) catch {
    Failure::Failure(message) => assert_true(message.contains("positive"))
    error => fail("unexpected Alibaba chat option error: \{error}")
  } noraise {
    _ => fail("expected invalid Alibaba thinking budget rejection")
  }
}

///|
test "Alibaba typed video options validate model-specific enums" {
  try
    AlibabaVideoMedia::new(media_type="audio", url="https://example.com")
  catch {
    Failure::Failure(message) => assert_true(message.contains("media_type"))
    error => fail("unexpected Alibaba media option error: \{error}")
  } noraise {
    _ => fail("expected invalid Alibaba media type rejection")
  }
  try AlibabaVideoModelOptions::new(shot_type="sequence") catch {
    Failure::Failure(message) => assert_true(message.contains("shot_type"))
    error => fail("unexpected Alibaba shot option error: \{error}")
  } noraise {
    _ => fail("expected invalid Alibaba shot type rejection")
  }
  try AlibabaVideoModelOptions::new(ratio="5:4") catch {
    Failure::Failure(message) => assert_true(message.contains("ratio"))
    error => fail("unexpected Alibaba ratio option error: \{error}")
  } noraise {
    _ => fail("expected invalid Alibaba ratio rejection")
  }
  try AlibabaVideoModelOptions::new(poll_interval_ms=0) catch {
    Failure::Failure(message) => assert_true(message.contains("poll_interval"))
    error => fail("unexpected Alibaba poll option error: \{error}")
  } noraise {
    _ => fail("expected invalid Alibaba poll interval rejection")
  }
  try AlibabaVideoModelOptions::new(poll_timeout_ms=0) catch {
    Failure::Failure(message) => assert_true(message.contains("poll_timeout"))
    error => fail("unexpected Alibaba timeout option error: \{error}")
  } noraise {
    _ => fail("expected invalid Alibaba poll timeout rejection")
  }
}

///|
test "Alibaba typed video options preserve legacy wire fields" {
  json_inspect(
    AlibabaVideoModelOptions::new(
      audio_url="https://example.com/audio.mp3",
      shot_type="single",
      audio=false,
      reference_urls=["https://example.com/reference.png"],
    ).to_provider_options(),
    content={
      "alibaba": {
        "audioUrl": "https://example.com/audio.mp3",
        "shotType": "single",
        "audio": false,
        "referenceUrls": ["https://example.com/reference.png"],
      },
    },
  )
}
