# moonai

A unified, provider-neutral AI SDK for MoonBit.

`moonai` brings the standard-layer design of
[Vercel AI SDK 7](https://ai-sdk.dev/) to MoonBit: one model interface,
normalized streaming events, provider adapters, tool calling, and a testable
core that applications can build on.

This is an independent community project and is not affiliated with Vercel.

> Status: early alpha. APIs may change before `1.0.0`. The current release
> supports the native target and provides OpenAI Responses, OpenAI-compatible
> Chat Completions, and Anthropic Messages streaming adapters.

## Current milestone

- Provider-neutral `ChatModel` interface.
- `stream_text` API with a `streamText` compatibility alias.
- Open Responses streaming over HTTP and SSE, used by the default OpenAI model.
- OpenAI-compatible Chat Completions streaming over HTTP and SSE.
- Anthropic Messages streaming over HTTP and SSE, including thinking and
  `tool_use` blocks.
- Normalized text, reasoning, tool-call, finish, error, and usage events.
- Incremental assembly of interleaved and parallel tool-call deltas.
- Mock models, golden SSE fixtures, and local HTTP integration tests.

## Packages

| Package | Purpose |
| --- | --- |
| `QuietlyChan/moonai` | Core model, message, tool, stream, and response types |
| `QuietlyChan/moonai/openai` | Official OpenAI provider that composes Responses and Chat Completions |
| `QuietlyChan/moonai/open_responses` | Reusable Open Responses protocol adapter |
| `QuietlyChan/moonai/openai_compatible` | Reusable OpenAI-compatible Chat Completions adapter |
| `QuietlyChan/moonai/anthropic` | Anthropic Messages API provider adapter |
| `QuietlyChan/moonai/testing` | Deterministic mock model for application tests |
| `QuietlyChan/moonai/cmd/main` | Optional executable smoke test; not required by the library |

## Installation

The package has not been published to Mooncakes yet. After the first release,
it will be installable with:

```shell
moon add QuietlyChan/moonai
```

Packages that use both the core API and the OpenAI adapter declare:

```moonbit nocheck
import {
  "QuietlyChan/moonai",
  "QuietlyChan/moonai/openai",
}
```

Import `QuietlyChan/moonai/openai_compatible` or
`QuietlyChan/moonai/open_responses` directly when building a third-party
provider package on one of those wire protocols.

## Streaming text

```moonbit nocheck
///|
let model = @openai.openai(
  "gpt-4.1-mini",
  api_key=@env.get_env_var("OPENAI_API_KEY").unwrap(),
)

///|
let result = @moonai.stream_text(
  model,
  prompt="Explain MoonBit in three sentences.",
  on_event=event => {
    match event {
      @moonai.TextDelta(delta~, ..) => @stdio.stdout.write(delta)
      _ => ()
    }
  },
)
```

MoonBit code should generally prefer `stream_text`. The `streamText` alias is
provided for developers familiar with the TypeScript AI SDK API.

`@openai.openai(...)` and `OpenAIProvider::language_model(...)` use the
Responses API by default, matching AI SDK 7. Use `@openai.openai_chat(...)` or
`OpenAIProvider::chat(...)` when Chat Completions is required:

```moonbit nocheck
///|
let chat_model = @openai.openai_chat(
  "gpt-4.1-mini",
  api_key=@env.get_env_var("OPENAI_API_KEY").unwrap(),
)
```

## Anthropic Messages

```moonbit nocheck
///|
let model = @anthropic.anthropic(
  "claude-sonnet-4-20250514",
  api_key=@env.get_env_var("ANTHROPIC_API_KEY").unwrap(),
)

///|
let response = @moonai.stream_text(
  model,
  prompt="Explain MoonBit in three sentences.",
  on_event=event => {
    match event {
      @moonai.TextDelta(delta~, ..) => @stdio.stdout.write(delta)
      @moonai.ReasoningDelta(delta~, ..) => ()
      _ => ()
    }
  },
)
```

## OpenAI-compatible providers

```moonbit nocheck
///|
let deepseek = @openai_compatible.openai_compatible(
  provider_name="deepseek",
  base_url="https://api.deepseek.com",
  model_id="deepseek-chat",
  api_key~,
  preserve_reasoning=true,
)

///|
let response = @moonai.stream_text(
  deepseek,
  prompt="What is MoonBit?",
  on_event=event => {
    match event {
      @moonai.TextDelta(delta~, ..) => @stdio.stdout.write(delta)
      _ => ()
    }
  },
)
```

The older `@openai.openai_compatible(...)` shortcut remains available, but new
provider integrations should depend on the standalone protocol package.

## Open Responses providers

```moonbit nocheck
///|
let provider = @open_responses.create_open_responses(
  provider_name="my-provider",
  url="https://example.com/v1/responses",
  api_key~,
)

///|
let model = provider.language_model("my-model")
```

The initial API intentionally follows familiar AI SDK concepts without
requiring MoonBit code to copy TypeScript naming everywhere:

| Vercel AI SDK | moonai |
| --- | --- |
| `streamText({ model, prompt })` | `@moonai.stream_text(model, prompt=...)` |
| `openai("gpt-4.1")` | `@openai.openai("gpt-4.1", api_key=...)` |
| `createOpenAI({ baseURL })` | `@openai.create_openai(base_url=..., api_key=...)` |
| `createOpenAICompatible(...)` | `@openai_compatible.create_openai_compatible(...)` |
| `createOpenResponses(...)` | `@open_responses.create_open_responses(...)` |
| `anthropic("claude-sonnet-4-20250514")` | `@anthropic.anthropic("claude-sonnet-4-20250514", api_key=...)` |

## Design direction

The core library will remain provider-neutral. Provider-specific wire formats,
authentication, and options belong in adapter packages. Planned milestones
include non-streaming generation, structured output, more provider adapters,
middleware, retries, telemetry hooks, and higher-level tool execution.

Agent workflows and sandboxed tool runtimes are intentionally later layers.
They will build on this SDK rather than being coupled to the provider protocol.

## Development

```shell
moon info
moon fmt --check
moon check
moon test
```

The optional smoke-test executable can be run with:

```shell
OPENAI_API_KEY=... moon run src/cmd/main
```

## License

Apache-2.0
