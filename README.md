# moonai

English | [简体中文](README.zh-CN.md)

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
> supports the native target, non-streaming and streaming text generation,
> embeddings, legacy completions, image generation, and Anthropic Messages.

## Current milestone

- Provider-neutral `ChatModel`, `EmbeddingModel`, `CompletionModel`, and
  `ImageModel` interfaces.
- `generate_text`, `stream_text`, `generate_object`, `embed`, `embed_many`,
  `complete`, `stream_completion`, and `generate_image` standard-layer APIs.
- Open Responses generation over JSON and streaming over SSE, used by the
  default OpenAI model.
- OpenAI-compatible Chat Completions generation over JSON and SSE, plus
  embeddings, legacy completions, and image generation.
- Anthropic Messages streaming over HTTP and SSE, including thinking and
  `tool_use` blocks.
- Text, URL/base64 image, audio, and file input parts, with explicit protocol
  validation when an adapter does not support a media type.
- Normalized text, reasoning, tool-call, finish, error, usage, and optional raw
  provider events.
- Incremental assembly of interleaved and parallel tool-call deltas.
- Standard sampling controls, JSON Schema response formats, and per-call HTTP
  headers that override provider defaults.
- Request/response diagnostics, provider metadata, typed warnings,
  configurable retries, and cooperative cancellation.
- Deterministic mock models for each core model interface, golden SSE fixtures,
  and local HTTP integration tests.

## Packages

| Package | Purpose |
| --- | --- |
| `QuietlyChan/moonai` | Core language, embedding, completion, image, tool, stream, and response APIs |
| `QuietlyChan/moonai/openai` | Official OpenAI provider composing the shared protocol implementations |
| `QuietlyChan/moonai/open_responses` | Reusable Open Responses protocol adapter |
| `QuietlyChan/moonai/openai_compatible` | Reusable Chat Completions, embeddings, completions, and image adapter |
| `QuietlyChan/moonai/anthropic` | Anthropic Messages API provider adapter |
| `QuietlyChan/moonai/testing` | Deterministic chat, embedding, completion, and image mock models |
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

Import `QuietlyChan/moonai/openai_compatible` or
`QuietlyChan/moonai/open_responses` directly when building a third-party
provider package on one of those wire protocols.

## Non-streaming text

```moonbit
///|
let model = @openai.openai(
  "gpt-4.1-mini",
  api_key=@env.get_env_var("OPENAI_API_KEY").unwrap(),
)

///|
let result = @moonai.generate_text(
  model,
  prompt="Explain MoonBit in three sentences.",
)
```

`generateText` is available as a compatibility alias.

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

Set `include_raw_chunks=true` to receive each parsed provider chunk as
`StreamEvent::Raw` before its normalized events. Text, completion, embedding,
and image calls also accept per-call `headers`; these override matching headers
configured on the provider.

## Diagnostics, retries, and cancellation

Every normalized response exposes `request`, `response`, `provider_metadata`,
and typed `warnings`. Non-streaming response metadata includes the original
body; streaming bodies are not buffered, so use `include_raw_chunks=true` when
the raw SSE payloads are required.

```moonbit
///|
let cancellation = @moonai.CancellationToken::new()

///|
let retry_policy = @moonai.RetryPolicy::new(
  max_retries=3,
  initial_delay_ms=200,
)

///|
let result = @moonai.generate_text(
  model,
  prompt="Explain MoonBit.",
  retry_policy~,
  cancellation_token=cancellation,
)
```

The default policy retries network failures, timeouts, HTTP 408/409/425/429,
and 5xx responses up to two times with exponential backoff. SSE calls retry
only before `StreamStart`, preventing duplicate text or tool events. Use
`RetryPolicy::none()` to disable retries and `cancellation.cancel()` to stop a
cooperative operation.

`@openai.openai(...)` and `OpenAIProvider::language_model(...)` use the
Responses API by default, matching AI SDK 7. Use `@openai.openai_chat(...)` or
`OpenAIProvider::chat(...)` when Chat Completions is required:

```moonbit
///|
let chat_model = @openai.openai_chat(
  "gpt-4.1-mini",
  api_key=@env.get_env_var("OPENAI_API_KEY").unwrap(),
)
```

## Anthropic Messages

```moonbit
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

```moonbit
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

```moonbit
///|
let provider = @open_responses.create_open_responses(
  provider_name="my-provider",
  url="https://example.com/v1/responses",
  api_key~,
)

///|
let model = provider.language_model("my-model")
```

## Structured output and multimodal input

```moonbit
///|
let object = @moonai.generate_object(
  model,
  {
    "type": "object",
    "properties": { "answer": { "type": "string" } },
    "required": ["answer"],
  },
  prompt="Answer as JSON.",
  name="answer",
)

///|
let response = @moonai.generate_text(
  model,
  messages=[
    @moonai.Message::user_parts([
      @moonai.ContentPart::text("Describe this image."),
      @moonai.ContentPart::image_url("https://example.com/moon.png"),
    ]),
  ],
)
```

OpenAI-compatible Chat Completions accepts text, image, audio, and file parts.
Open Responses accepts text, image, and file parts and rejects audio input
explicitly. `generate_object` requests JSON Schema output and parses the final
JSON value; schema validation of the returned value is not implemented yet.

## Embeddings, completions, and images

The official OpenAI provider and the OpenAI-compatible provider expose the
same model selectors:

```moonbit
///|
let provider = @openai.create_openai(api_key~)

///|
let vector = @moonai.embed(
  provider.embedding("text-embedding-3-small"),
  "MoonBit",
)

///|
let completion = @moonai.complete(
  provider.completion("gpt-3.5-turbo-instruct"),
  "MoonBit is",
)

///|
let images = @moonai.generate_image(
  provider.image("gpt-image-1"),
  "A precise MoonBit language logo",
  n=2,
  size="1024x1024",
)
```

`embed_many` and `generate_image` split requests at the model's per-call limit,
preserve result order, validate response counts, and accumulate usage.
Generated payloads are tagged as `ImageData::Base64` or `ImageData::Url`.

The initial API intentionally follows familiar AI SDK concepts without
requiring MoonBit code to copy TypeScript naming everywhere:

| Vercel AI SDK | moonai |
| --- | --- |
| `generateText({ model, prompt })` | `@moonai.generate_text(model, prompt=...)` |
| `streamText({ model, prompt })` | `@moonai.stream_text(model, prompt=...)` |
| `generateObject({ model, schema })` | `@moonai.generate_object(model, schema, ...)` |
| `embed({ model, value })` | `@moonai.embed(model, value)` |
| `embedMany({ model, values })` | `@moonai.embed_many(model, values)` |
| `generateImage({ model, prompt })` | `@moonai.generate_image(model, prompt)` |
| `openai("gpt-4.1")` | `@openai.openai("gpt-4.1", api_key=...)` |
| `createOpenAI({ baseURL })` | `@openai.create_openai(base_url=..., api_key=...)` |
| `createOpenAICompatible(...)` | `@openai_compatible.create_openai_compatible(...)` |
| `createOpenResponses(...)` | `@open_responses.create_open_responses(...)` |
| `anthropic("claude-sonnet-4-20250514")` | `@anthropic.anthropic("claude-sonnet-4-20250514", api_key=...)` |

## Design direction

The core library will remain provider-neutral. Provider-specific wire formats,
authentication, and options belong in adapter packages. Planned milestones
include richer generated content such as sources and files, image editing,
middleware, telemetry hooks, and higher-level multi-step tool execution.

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
