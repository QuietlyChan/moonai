# moonai

[![CI](https://github.com/QuietlyChan/moonai/actions/workflows/ci.yml/badge.svg)](https://github.com/QuietlyChan/moonai/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![MoonBit](https://img.shields.io/badge/MoonBit-native-F5A623.svg)](https://www.moonbitlang.com/)

A unified, provider-neutral AI SDK for MoonBit.

`moonai` brings the standard-layer design of
[Vercel AI SDK 7](https://ai-sdk.dev/) to MoonBit: one model interface,
normalized streaming events, provider adapters, tool calling, and a testable
core that applications can build on.

This is an independent community project and is not affiliated with Vercel.

> Status: early alpha. APIs may change before `1.0.0`. The current release
> supports the native target and focuses on OpenAI-compatible streaming.

## Current milestone

- Provider-neutral `ChatModel` interface.
- `stream_text` API with a `streamText` compatibility alias.
- OpenAI-compatible Chat Completions streaming over HTTP and SSE.
- Normalized text, reasoning, tool-call, finish, error, and usage events.
- Incremental assembly of interleaved and parallel tool-call deltas.
- Mock models, golden SSE fixtures, and local HTTP integration tests.

## Packages

| Package | Purpose |
| --- | --- |
| `QuietlyChan/moonai` | Core model, message, tool, stream, and response types |
| `QuietlyChan/moonai/openai` | OpenAI and OpenAI-compatible provider adapter |
| `QuietlyChan/moonai/testing` | Deterministic mock model for application tests |
| `QuietlyChan/moonai/cmd/main` | Optional executable smoke test; not required by the library |

## Installation

The package has not been published to Mooncakes yet. After the first release,
it will be installable with:

```shell
moon add QuietlyChan/moonai
```

Packages that use both the core API and the OpenAI adapter declare:

```moonbit
import {
  "QuietlyChan/moonai",
  "QuietlyChan/moonai/openai",
}
```

## Streaming text

```moonbit
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

## OpenAI-compatible providers

```moonbit
///|
let deepseek = @openai.openai_compatible(
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

The initial API intentionally follows familiar AI SDK concepts without
requiring MoonBit code to copy TypeScript naming everywhere:

| Vercel AI SDK | moonai |
| --- | --- |
| `streamText({ model, prompt })` | `@moonai.stream_text(model, prompt=...)` |
| `openai("gpt-4.1")` | `@openai.openai("gpt-4.1", api_key=...)` |
| `createOpenAI({ baseURL })` | `@openai.create_openai(base_url=..., api_key=...)` |

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

MoonBit-aware documentation is maintained in
[`README.mbt.md`](README.mbt.md).

## License

Licensed under the [Apache License 2.0](LICENSE).
