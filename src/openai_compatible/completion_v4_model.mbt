///|
/// V4 language-model boundary for an OpenAI-compatible `/completions`
/// endpoint.
pub struct OpenAICompatibleCompletionLanguageModelV4 {
  model : OpenAICompatibleCompletionModel
}

///|
/// Construct the V4 wrapper for an OpenAI-compatible completion wire model.
pub fn OpenAICompatibleCompletionLanguageModelV4::new(
  model : OpenAICompatibleCompletionModel,
) -> OpenAICompatibleCompletionLanguageModelV4 {
  { model, }
}

///|
fn compatible_completion_v4_warnings(
  options : @provider.LanguageModelV4CallOptions,
) -> Array[@provider.Warning] {
  let warnings : Array[@provider.Warning] = []
  if options.tools.length() > 0 {
    warnings.push(@provider.Warning::unsupported("tools"))
  }
  if options.tool_choice is Some(_) {
    warnings.push(@provider.Warning::unsupported("toolChoice"))
  }
  match options.response_format {
    @provider.Text => ()
    @provider.JsonResponse(_) =>
      warnings.push(@provider.Warning::unsupported("responseFormat"))
  }
  warnings
}

///|
fn compatible_completion_v4_options(
  options : @provider.LanguageModelV4CallOptions,
) -> @provider.CompletionOptions raise {
  let converted = @provider_utils.convert_to_completion_prompt(options.prompt)
  let stop_sequences = converted.stop_sequences.copy()
  for value in options.stop_sequences {
    stop_sequences.push(value)
  }
  @provider.CompletionOptions::new(
    converted.prompt,
    max_output_tokens?=options.max_output_tokens,
    temperature?=options.temperature,
    top_p?=options.top_p,
    top_k?=options.top_k,
    frequency_penalty?=options.frequency_penalty,
    presence_penalty?=options.presence_penalty,
    seed?=options.seed,
    stop_sequences~,
    include_raw_chunks=options.include_raw_chunks,
    headers=options.headers,
    provider_options=options.provider_options,
    retry_policy=options.retry_policy,
    cancellation_token?=options.cancellation_token,
  )
}

///|
fn append_compatible_completion_warnings(
  extra : Array[@provider.Warning],
  existing : Array[@provider.Warning],
) -> Array[@provider.Warning] {
  let warnings = @provider.copy_warnings(extra)
  for warning in existing {
    warnings.push(warning)
  }
  warnings
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleCompletionLanguageModelV4 with fn specification_version(
  _self,
) -> String {
  "v4"
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleCompletionLanguageModelV4 with fn provider(
  self,
) -> String {
  self.model.provider()
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleCompletionLanguageModelV4 with fn model_id(
  self,
) -> String {
  self.model.model_id()
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleCompletionLanguageModelV4 with fn supported_urls(
  _self,
) -> Array[@provider.SupportedUrlRule] {
  []
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleCompletionLanguageModelV4 with fn do_generate(
  self,
  options,
) {
  let wrapper_warnings = compatible_completion_v4_warnings(options)
  let response = self.model.generate_completion(
    compatible_completion_v4_options(options),
  )
  let response = response.with_diagnostics(
    response.request,
    response.response,
    response.provider_metadata,
    append_compatible_completion_warnings(wrapper_warnings, response.warnings),
  )
  let raw = compatible_v4_response_json(response.response)
  @provider.LanguageModelV4GenerateResult::from_completion_response(response).with_usage_and_finish_reason(
    @provider.LanguageModelV4Usage::from_usage(response.usage).with_raw(
      compatible_v4_raw_usage(raw),
    ),
    @provider.LanguageModelV4FinishReason::from_finish_reason(
      response.finish_reason,
    ).with_raw(compatible_v4_raw_finish_reason(raw)),
  )
}

///|
pub impl @provider.LanguageModelV4 for OpenAICompatibleCompletionLanguageModelV4 with fn do_stream(
  self,
  options,
  on_event,
) {
  let wrapper_warnings = compatible_completion_v4_warnings(options)
  let response = self.model.stream_completion(
    compatible_completion_v4_options(options),
    event => {
      match event {
        @provider.StreamStart =>
          on_event(
            @provider.V4StreamStart(
              warnings=@provider.copy_warnings(wrapper_warnings),
            ),
          )
        other =>
          on_event(
            @provider.LanguageModelV4StreamPart::from_stream_event(other),
          )
      }
    },
  )
  let warnings = append_compatible_completion_warnings(
    wrapper_warnings,
    response.warnings,
  )
  @provider.LanguageModelV4StreamResult::new(
    response.request,
    response.response,
    usage=@provider.LanguageModelV4Usage::from_usage(response.usage),
    finish_reason=@provider.LanguageModelV4FinishReason::from_finish_reason(
      response.finish_reason,
    ),
    provider_metadata=response.provider_metadata,
    warnings~,
  )
}
