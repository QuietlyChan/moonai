///|
/// Middleware that fills missing call settings with the provided defaults,
/// mirroring AI SDK's `defaultSettingsMiddleware`.
///
/// Only unset fields are filled; values the caller provided explicitly always
/// win, and headers are merged with call-level headers taking precedence.
pub fn default_settings_middleware(
  defaults : @provider.LanguageModelV4CallOptions,
) -> @provider.LanguageModelV4Middleware {
  @provider.LanguageModelV4Middleware::new(transform_params=fn(context) {
    let params = context.params
    let merged_headers = @provider_utils.merge_headers(
      defaults.headers,
      params.headers,
    )
    {
      prompt: params.prompt,
      tools: params.tools,
      tool_choice: params.tool_choice,
      response_format: params.response_format,
      reasoning: if params.reasoning is @provider.V4ReasoningProviderDefault {
        defaults.reasoning
      } else {
        params.reasoning
      },
      max_output_tokens: match params.max_output_tokens {
        Some(value) => Some(value)
        None => defaults.max_output_tokens
      },
      temperature: match params.temperature {
        Some(value) => Some(value)
        None => defaults.temperature
      },
      top_p: match params.top_p {
        Some(value) => Some(value)
        None => defaults.top_p
      },
      top_k: match params.top_k {
        Some(value) => Some(value)
        None => defaults.top_k
      },
      frequency_penalty: match params.frequency_penalty {
        Some(value) => Some(value)
        None => defaults.frequency_penalty
      },
      presence_penalty: match params.presence_penalty {
        Some(value) => Some(value)
        None => defaults.presence_penalty
      },
      seed: match params.seed {
        Some(value) => Some(value)
        None => defaults.seed
      },
      stop_sequences: if params.stop_sequences.length() > 0 {
        params.stop_sequences
      } else {
        defaults.stop_sequences
      },
      include_raw_chunks: params.include_raw_chunks,
      headers: merged_headers,
      provider_options: params.provider_options,
      retry_policy: params.retry_policy,
      cancellation_token: params.cancellation_token,
    }
  })
}
