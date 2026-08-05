///|
fn openai_realtime_object_field(json : Json, field : String) -> Json? {
  match json {
    Object(values) => values.get(field)
    _ => None
  }
}

///|
fn openai_realtime_nested_string(
  json : Json,
  object_field : String,
  field : String,
) -> String? {
  match openai_realtime_object_field(json, object_field) {
    Some(value) => @provider_utils.json_string_field(value, field)
    None => None
  }
}

///|
fn openai_realtime_audio_format(format : @provider.AudioFormat) -> Json {
  let fields : Map[String, Json] = Map([
    ("type", Json::string(format.media_type)),
  ])
  if format.sample_rate is Some(rate) {
    fields["rate"] = Json::number(rate.to_double())
  }
  Json::object(fields)
}

///|
fn openai_realtime_transcription_config(
  config : @provider.RealtimeAudioTranscriptionConfig,
) -> Json {
  let fields : Map[String, Json] = Map([
    ("model", Json::string(config.model.unwrap_or("gpt-realtime-whisper"))),
  ])
  if config.language is Some(language) {
    fields["language"] = Json::string(language)
  }
  if config.prompt is Some(prompt) {
    fields["prompt"] = Json::string(prompt)
  }
  Json::object(fields)
}

///|
fn openai_realtime_turn_detection(
  config : @provider.RealtimeTurnDetection,
) -> Json {
  match config {
    @provider.RealtimeTurnDetectionDisabled => Json::null()
    @provider.RealtimeServerVad(
      threshold~,
      silence_duration_ms~,
      prefix_padding_ms~
    ) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("server_vad")),
      ])
      if threshold is Some(value) {
        fields["threshold"] = Json::number(value)
      }
      if silence_duration_ms is Some(value) {
        fields["silence_duration_ms"] = Json::number(value.to_double())
      }
      if prefix_padding_ms is Some(value) {
        fields["prefix_padding_ms"] = Json::number(value.to_double())
      }
      Json::object(fields)
    }
    @provider.RealtimeSemanticVad(
      threshold~,
      silence_duration_ms~,
      prefix_padding_ms~
    ) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("semantic_vad")),
      ])
      if threshold is Some(value) {
        fields["threshold"] = Json::number(value)
      }
      if silence_duration_ms is Some(value) {
        fields["silence_duration_ms"] = Json::number(value.to_double())
      }
      if prefix_padding_ms is Some(value) {
        fields["prefix_padding_ms"] = Json::number(value.to_double())
      }
      Json::object(fields)
    }
  }
}

///|
/// Build OpenAI's Realtime `session` object from the provider-neutral V4
/// configuration.
pub fn build_openai_realtime_session_config(
  config : @provider.RealtimeSessionConfig,
  model_id : String,
) -> Json {
  let session : Map[String, Json] = Map([
    ("type", Json::string("realtime")),
    ("model", Json::string(model_id)),
  ])
  if config.instructions is Some(value) {
    session["instructions"] = Json::string(value)
  }
  if config.output_modalities is Some(modalities) {
    let values : Array[Json] = []
    for modality in modalities {
      values.push(
        match modality {
          @provider.RealtimeText => Json::string("text")
          @provider.RealtimeAudio => Json::string("audio")
        },
      )
    }
    session["output_modalities"] = Json::array(values)
  }
  let audio : Map[String, Json] = Map([])
  if config.input_audio_format is Some(_) ||
    config.input_audio_transcription is Some(_) ||
    config.turn_detection is Some(_) {
    let input : Map[String, Json] = Map([])
    if config.input_audio_format is Some(value) {
      input["format"] = openai_realtime_audio_format(value)
    }
    if config.turn_detection is Some(value) {
      input["turn_detection"] = openai_realtime_turn_detection(value)
    }
    if config.input_audio_transcription is Some(value) {
      input["transcription"] = openai_realtime_transcription_config(value)
    }
    audio["input"] = Json::object(input)
  }
  if config.output_audio_format is Some(_) || config.voice is Some(_) {
    let output : Map[String, Json] = Map([])
    if config.output_audio_format is Some(value) {
      output["format"] = openai_realtime_audio_format(value)
    }
    if config.voice is Some(value) {
      output["voice"] = Json::string(value)
    }
    audio["output"] = Json::object(output)
  }
  if audio.length() > 0 {
    session["audio"] = Json::object(audio)
  }
  if config.tools.length() > 0 {
    let tools : Array[Json] = []
    for tool in config.tools {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("function")),
        ("name", Json::string(tool.name)),
      ])
      if tool.description is Some(value) {
        fields["description"] = Json::string(value)
      }
      fields["parameters"] = tool.parameters
      tools.push(Json::object(fields))
    }
    session["tools"] = Json::array(tools)
    session["tool_choice"] = Json::string("auto")
  }
  for entry in config.provider_options.iter2() {
    let (key, value) = entry
    session[key] = value
  }
  Json::object(session)
}

///|
/// Serialize one normalized realtime client event to OpenAI's wire format.
pub fn serialize_openai_realtime_client_event(
  event : @provider.RealtimeClientEvent,
  model_id : String,
) -> Json {
  match event {
    @provider.RealtimeSessionUpdate(config) =>
      {
        "type": "session.update",
        "session": build_openai_realtime_session_config(config, model_id),
      }
    @provider.RealtimeInputAudioAppend(audio) =>
      { "type": "input_audio_buffer.append", "audio": audio }
    @provider.RealtimeInputAudioCommit =>
      { "type": "input_audio_buffer.commit" }
    @provider.RealtimeInputAudioClear => { "type": "input_audio_buffer.clear" }
    @provider.RealtimeConversationItemCreate(item) => {
      let wire_item : Json = match item {
        @provider.RealtimeTextMessage(text~) =>
          {
            "type": "message",
            "role": "user",
            "content": [{ "type": "input_text", "text": text }],
          }
        @provider.RealtimeAudioMessage(audio~) =>
          {
            "type": "message",
            "role": "user",
            "content": [{ "type": "input_audio", "audio": audio }],
          }
        @provider.RealtimeFunctionCallOutput(call_id~, output~, ..) =>
          {
            "type": "function_call_output",
            "call_id": call_id,
            "output": output,
          }
      }
      { "type": "conversation.item.create", "item": wire_item }
    }
    @provider.RealtimeConversationItemTruncate(
      item_id~,
      content_index~,
      audio_end_ms~
    ) =>
      {
        "type": "conversation.item.truncate",
        "item_id": item_id,
        "content_index": content_index,
        "audio_end_ms": audio_end_ms,
      }
    @provider.RealtimeResponseCreate(options) => {
      let fields : Map[String, Json] = Map([
        ("type", Json::string("response.create")),
      ])
      if options is Some(value) {
        let response : Map[String, Json] = Map([])
        if value.modalities is Some(modalities) {
          response["output_modalities"] = Json::array(
            [
              for modality in modalities => Json::string(modality)
            ],
          )
        }
        if value.instructions is Some(instructions) {
          response["instructions"] = Json::string(instructions)
        }
        if value.metadata is Some(metadata) {
          response["metadata"] = Json::object(
            @provider.copy_provider_metadata(metadata),
          )
        }
        fields["response"] = Json::object(response)
      }
      Json::object(fields)
    }
    @provider.RealtimeResponseCancel => { "type": "response.cancel" }
  }
}

///|
fn openai_realtime_item_id(raw : Json) -> String {
  openai_realtime_nested_string(raw, "item", "id").unwrap_or(
    @provider_utils.json_string_field(raw, "item_id").unwrap_or(""),
  )
}

///|
fn openai_realtime_response_id(raw : Json) -> String {
  openai_realtime_nested_string(raw, "response", "id").unwrap_or(
    @provider_utils.json_string_field(raw, "response_id").unwrap_or(""),
  )
}

///|
/// Parse one OpenAI Realtime server event into the provider-neutral V4 event
/// union.
pub fn parse_openai_realtime_server_event(
  raw : Json,
) -> @provider.RealtimeServerEvent {
  let event_type = @provider_utils.json_string_field(raw, "type").unwrap_or("")
  let item_id = @provider_utils.json_string_field(raw, "item_id").unwrap_or("")
  let response_id = @provider_utils.json_string_field(raw, "response_id").unwrap_or(
    "",
  )
  match event_type {
    "session.created" =>
      @provider.RealtimeSessionCreated(
        session_id=openai_realtime_nested_string(raw, "session", "id"),
        raw~,
      )
    "session.updated" => @provider.RealtimeSessionUpdated(raw~)
    "input_audio_buffer.speech_started" =>
      @provider.RealtimeSpeechStarted(
        item_id=@provider_utils.json_string_field(raw, "item_id"),
        raw~,
      )
    "input_audio_buffer.speech_stopped" =>
      @provider.RealtimeSpeechStopped(
        item_id=@provider_utils.json_string_field(raw, "item_id"),
        raw~,
      )
    "input_audio_buffer.committed" =>
      @provider.RealtimeAudioCommitted(
        item_id=@provider_utils.json_string_field(raw, "item_id"),
        previous_item_id=@provider_utils.json_string_field(
          raw, "previous_item_id",
        ),
        raw~,
      )
    "conversation.item.added" =>
      @provider.RealtimeConversationItemAdded(
        item_id=openai_realtime_item_id(raw),
        item=openai_realtime_object_field(raw, "item").unwrap_or(
          Json::empty_object(),
        ),
        raw~,
      )
    "conversation.item.input_audio_transcription.completed" =>
      @provider.RealtimeInputTranscriptionCompleted(
        item_id~,
        transcript=@provider_utils.json_string_field(raw, "transcript").unwrap_or(
          "",
        ),
        raw~,
      )
    "response.created" =>
      @provider.RealtimeResponseCreated(
        response_id=openai_realtime_response_id(raw),
        raw~,
      )
    "response.done" =>
      @provider.RealtimeResponseDone(
        response_id=openai_realtime_response_id(raw),
        status=openai_realtime_nested_string(raw, "response", "status").unwrap_or(
          "completed",
        ),
        raw~,
      )
    "response.output_item.added" =>
      @provider.RealtimeOutputItemAdded(
        response_id~,
        item_id=openai_realtime_item_id(raw),
        raw~,
      )
    "response.output_item.done" =>
      @provider.RealtimeOutputItemDone(
        response_id~,
        item_id=openai_realtime_item_id(raw),
        raw~,
      )
    "response.content_part.added" =>
      @provider.RealtimeContentPartAdded(response_id~, item_id~, raw~)
    "response.content_part.done" =>
      @provider.RealtimeContentPartDone(response_id~, item_id~, raw~)
    "response.output_audio.delta" =>
      @provider.RealtimeAudioDelta(
        response_id~,
        item_id~,
        delta=@provider_utils.json_string_field(raw, "delta").unwrap_or(""),
        raw~,
      )
    "response.output_audio.done" =>
      @provider.RealtimeAudioDone(response_id~, item_id~, raw~)
    "response.output_audio_transcript.delta" =>
      @provider.RealtimeAudioTranscriptDelta(
        response_id~,
        item_id~,
        delta=@provider_utils.json_string_field(raw, "delta").unwrap_or(""),
        raw~,
      )
    "response.output_audio_transcript.done" =>
      @provider.RealtimeAudioTranscriptDone(
        response_id~,
        item_id~,
        transcript=@provider_utils.json_string_field(raw, "transcript"),
        raw~,
      )
    "response.output_text.delta" =>
      @provider.RealtimeTextDelta(
        response_id~,
        item_id~,
        delta=@provider_utils.json_string_field(raw, "delta").unwrap_or(""),
        raw~,
      )
    "response.output_text.done" =>
      @provider.RealtimeTextDone(
        response_id~,
        item_id~,
        text=@provider_utils.json_string_field(raw, "text"),
        raw~,
      )
    "response.function_call_arguments.delta" =>
      @provider.RealtimeFunctionCallArgumentsDelta(
        response_id~,
        item_id~,
        call_id=@provider_utils.json_string_field(raw, "call_id").unwrap_or(""),
        delta=@provider_utils.json_string_field(raw, "delta").unwrap_or(""),
        raw~,
      )
    "response.function_call_arguments.done" =>
      @provider.RealtimeFunctionCallArgumentsDone(
        response_id~,
        item_id~,
        call_id=@provider_utils.json_string_field(raw, "call_id").unwrap_or(""),
        name=@provider_utils.json_string_field(raw, "name").unwrap_or(""),
        arguments=@provider_utils.json_string_field(raw, "arguments").unwrap_or(
          "",
        ),
        raw~,
      )
    "error" => {
      let error_code = match
        openai_realtime_nested_string(raw, "error", "code") {
        Some(value) => Some(value)
        None => @provider_utils.json_string_field(raw, "code")
      }
      @provider.RealtimeError(
        message=openai_realtime_nested_string(raw, "error", "message").unwrap_or(
          @provider_utils.json_string_field(raw, "message").unwrap_or(
            "Unknown error",
          ),
        ),
        code=error_code,
        raw~,
      )
    }
    value => @provider.RealtimeCustom(raw_type=value, raw~)
  }
}
