///|
/// Transitional V4 adapter for a provider model that still implements the
/// original Moonai `ChatModel` contract.
///
/// This wrapper keeps the public boundary versioned like AI SDK while each
/// provider can migrate its wire implementation independently.
pub struct ChatModelV4Adapter {
  model : &@provider.ChatModel
}

///|
/// Construct a V4 adapter around an existing chat model.
pub fn ChatModelV4Adapter::new(
  model : &@provider.ChatModel,
) -> ChatModelV4Adapter {
  { model, }
}

///|
/// Adapt an existing chat model to the AI SDK V4 language-model contract.
pub fn as_language_model_v4(
  model : &@provider.ChatModel,
) -> &@provider.LanguageModelV4 {
  ChatModelV4Adapter::{ model, } as &@provider.LanguageModelV4
}

///|
/// AI SDK-style camel-case spelling for `as_language_model_v4`.
pub fn asLanguageModelV4(
  model : &@provider.ChatModel,
) -> &@provider.LanguageModelV4 {
  as_language_model_v4(model)
}

///|
pub impl @provider.LanguageModelV4 for ChatModelV4Adapter with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for ChatModelV4Adapter with fn provider(self) -> String {
  self.model.provider()
}

///|
pub impl @provider.LanguageModelV4 for ChatModelV4Adapter with fn model_id(self) -> String {
  self.model.model_id()
}

///|
pub impl @provider.LanguageModelV4 for ChatModelV4Adapter with fn supported_urls(
  self,
) -> Array[@provider.SupportedUrlRule] {
  self.model.supported_urls()
}

///|
pub impl @provider.LanguageModelV4 for ChatModelV4Adapter with fn do_generate(
  self,
  options,
) {
  let response = self.model.generate(options.to_chat_call_options())
  @provider.LanguageModelV4GenerateResult::from_chat_response(response)
}

///|
pub impl @provider.LanguageModelV4 for ChatModelV4Adapter with fn do_stream(
  self,
  options,
  on_event,
) {
  let started : Ref[Bool] = Ref(false)
  let warnings : Array[@provider.Warning] = []
  let response = self.model.stream(options.to_chat_call_options(), event => {
    match event {
      @provider.StreamStart => ()
      @provider.Warning(warning) if !started.val => warnings.push(warning)
      @provider.Warning(_) => ()
      @provider.Finish(..) => ()
      other => {
        if !started.val {
          started.val = true
          on_event(
            @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
          )
        }
        match @provider.LanguageModelV4StreamPart::from_stream_event(other) {
          Some(part) => on_event(part)
          None => ()
        }
      }
    }
  })
  if !started.val {
    for warning in response.warnings {
      if !warnings.contains(warning) {
        warnings.push(warning)
      }
    }
    started.val = true
    on_event(
      @provider.V4StreamStart(warnings=@provider.copy_warnings(warnings)),
    )
  }
  on_event(
    @provider.V4Finish(
      usage=@provider.LanguageModelV4Usage::from_usage(response.usage),
      reason=@provider.LanguageModelV4FinishReason::from_finish_reason(
        response.finish_reason,
      ),
      provider_metadata=@provider.copy_provider_metadata(
        response.provider_metadata,
      ),
    ),
  )
  @provider.LanguageModelV4StreamResult::new(
    response.request,
    response.response,
  )
}
