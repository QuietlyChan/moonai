# moonai

A unified, provider-neutral AI SDK for MoonBit.

`moonai` brings the standard-layer design of
[Vercel AI SDK 7](https://ai-sdk.dev/) to MoonBit: one model interface,
normalized streaming events, provider adapters, tool calling, and a testable
core that applications can build on.

This is an independent community project and is not affiliated with Vercel.

> Status: early alpha. APIs may change before `1.0.0`. The current release
> supports the native target, non-streaming and streaming text generation,
> embeddings, legacy completions, image generation, Anthropic Messages,
> Alibaba DashScope, DeepSeek, and MiniMax adapters.

## Current milestone

- Provider-neutral text, embedding, image, video, speech, transcription,
  translation, realtime, Files, and Skills model/service contracts.
- `generate_text`, `stream_text`, `generate_object`, `embed`, `embed_many`,
  media generation, upload, buffered transcription, and live
  `stream_transcribe` standard-layer APIs.
- Shared multi-step tool execution for `generate_text` and `stream_text`,
  including `prepare_step` model/message/settings overrides, active tool
  filtering and ordering, stop conditions, provider-deferred results,
  sandbox-aware dynamic descriptions, and experimental tool caller routing.
- Reusable Open Responses generation over JSON and streaming over SSE, plus a
  separate official OpenAI Responses model and options layer.
- OpenAI-compatible Chat Completions generation over JSON and SSE, plus
  embeddings, legacy completions, and image generation.
- Anthropic Messages non-streaming generation over JSON and streaming over SSE,
  including thinking and `tool_use` blocks.
- Alibaba DashScope Chat Completions, native text embeddings, and asynchronous
  video generation.
- DeepSeek Chat Completions with reasoning controls and streaming usage.
- MiniMax Chat Completions and asynchronous video generation with polling.
- OpenAI buffered audio transcription and Realtime Whisper transcription over
  the provider-neutral `AudioStream` contract.
- Text, URL/base64 image, audio, and file input parts, with explicit protocol
  validation when an adapter does not support a media type.
- Normalized text, reasoning, tool-call, finish, error, usage, and optional raw
  provider events.
- Incremental assembly of interleaved and parallel tool-call deltas.
- Standard sampling and reasoning controls, JSON Schema response formats,
  namespaced provider options, and per-call HTTP headers that override
  provider defaults.
- Request/response diagnostics, provider metadata, typed warnings,
  configurable retries, and cooperative cancellation.
- Deterministic mock models for each core model interface, golden SSE fixtures,
  and local HTTP integration tests.

## Packages

| Package | Purpose |
| --- | --- |
| `QuietlyChan/moonai/ai` | High-level generation, embedding, media, upload, and realtime workflows |
| `QuietlyChan/moonai/ai/generate_text` | Multi-step text generation, per-step preparation, streaming, tool execution, and result aggregation |
| `QuietlyChan/moonai/ai/tool` | Tool caller routing and per-step tool preparation |
| `QuietlyChan/moonai/ai/prompt` | Prompt URL/file normalization and model-supported asset downloading |
| `QuietlyChan/moonai/ai/model` | Provider-qualified model identities, references, and registry resolution |
| `QuietlyChan/moonai/ai/registry` | Provider-qualified model lookup and provider-level Files/Skills registry |
| `QuietlyChan/moonai/provider` | Provider-neutral model contracts, call options, responses, events, and diagnostics |
| `QuietlyChan/moonai/provider_utils` | Reusable tool and sandbox contracts, HTTP, SSE, JSON, multipart, URL, WebSocket, retry, and streaming helpers |
| `QuietlyChan/moonai/openai` | Official OpenAI Chat and Responses models with typed options and model capabilities |
| `QuietlyChan/moonai/open_responses` | Reusable Open Responses protocol encoder, decoder, and transport |
| `QuietlyChan/moonai/openai_compatible` | Reusable Chat Completions, embeddings, completions, and image adapter |
| `QuietlyChan/moonai/anthropic` | Anthropic Messages, Files, and Skills API provider adapter |
| `QuietlyChan/moonai/alibaba` | Alibaba DashScope Chat, embeddings, and video adapter |
| `QuietlyChan/moonai/deepseek` | DeepSeek Chat Completions adapter |
| `QuietlyChan/moonai/minimax` | MiniMax Chat and video adapter |
| `QuietlyChan/moonai/testing` | Deterministic mocks for the provider-neutral model contracts |
| `QuietlyChan/moonai/cmd/main` | Optional executable smoke test; not required by the library |

These foundational packages correspond to AI SDK's `packages/ai`,
`packages/provider`, `packages/provider-utils`, and the registry portions of
`packages/ai`. Provider implementations
depend on `provider` and `provider_utils`; applications normally combine `ai`,
`provider`, and one concrete provider package. MoonBit enum constructors are
not re-exportable, so values such as `V4TextDelta`, `V4FinishStop`, and `High` are used
through the `@provider` package directly.

The `src` tree follows the same dependency boundaries while preserving the
useful internal domains from the TypeScript SDK. `src/ai`,
`src/ai/generate_text`, `src/ai/tool`, `src/ai/prompt`, `src/ai/model`,
`src/ai/registry`, `src/provider`, and `src/provider_utils` are MoonBit
packages.
A source domain becomes a package when it has a stable dependency boundary;
smaller helpers remain grouped by responsibility inside their owning package.
There is intentionally no module-root compatibility package. The pre-`1.0.0`
API is allowed to evolve, so consumers should import the named packages above
directly. The old `src/internal` implementation package has also been removed.

Source directories and abstractions are not the same boundary. The important
domains are represented by real MoonBit abstractions: the caller-facing
language, embedding, and image contracts are `LanguageModelV4`,
`EmbeddingModelV4`, and `ImageModelV4`; prompt normalization is isolated in
`ai/prompt`; and replaceable provider HTTP is the `HttpTransport` trait in
`provider_utils`. Every provider factory accepts an
optional `http_transport` and propagates it to buffered, streaming, multipart,
binary, download, and polling requests. `ChatModel`, `EmbeddingWireModel`, and
`ImageWireModel` are reserved for explicit wire and third-party adapter
boundaries, not the high-level model API.

`provider` defines the V4 middleware contracts for language, embedding, and
image models, while `ai/model` owns their wrapper/chain helpers. This matches
AI SDK's package boundary: provider and middleware libraries share contract
types without depending on high-level workflows. `ProviderRegistry` accepts
language and image V4 middleware and applies parameter transforms, identity
overrides, and operation wrappers after model resolution. The current
`ChatModel`-to-V4 adapter is reserved for explicit third-party and wire-level
integration boundaries.

The public `ModelMessage` and `ModelContentPart` types are defined in
`provider_utils`, matching AI SDK's shared prompt types. `ai/prompt` converts
them into the separate `provider::LanguageModelMessage` prompt contract. A
provider encoder therefore cannot accidentally receive an unvalidated
high-level message.

AI SDK's `packages/ai/src/model` does not define the provider model contracts.
It resolves string model identifiers and adapts older V2/V3 contracts to V4.
Moonai keeps the call contracts in `provider`, while `ai/model` owns
provider-qualified `ModelId`, direct/named model references, typed registries,
and version adapters. All bundled language providers expose provider-owned
`LanguageModelV4` implementations; the generic `as_language_model_v4` adapter
is reserved for explicit third-party and wire-level integrations.
The two registries have different ownership. `ai/model::ModelRegistry` stores
already-constructed model instances by canonical identity. In contrast,
`ai/registry::ProviderRegistry` stores provider factories, selects a model
lazily from a `provider:model` id, and exposes provider-level Files and Skills
capabilities. The latter mirrors AI SDK's `createProviderRegistry` layer.

`ai/registry::custom_provider` mirrors AI SDK's `customProvider`: applications
can inject their own V4 language, embedding, image, media, or audio models by
contract.
Unmatched models and Files/Skills capabilities are delegated to an optional
`fallback_provider`. This lets `provider` traits, `ai/prompt`, and
`provider_utils::HttpTransport` compose at the application boundary without a
module-root compatibility facade.

## Installation

The package has not been published to Mooncakes yet. After the first release,
it will be installable with:

```shell
moon add QuietlyChan/moonai
```

Packages that use both the core API and the OpenAI adapter declare:

```moonbit nocheck
import {
  "QuietlyChan/moonai/ai",
  "QuietlyChan/moonai/provider",
  "QuietlyChan/moonai/openai",
}
```

Import `QuietlyChan/moonai/openai_compatible` or
`QuietlyChan/moonai/open_responses` directly when building a third-party
provider package on one of those wire protocols.

## Non-streaming text

```moonbit nocheck
///|
let model = @openai.openai(
  "gpt-4.1-mini",
  api_key=@env.get_env_var("OPENAI_API_KEY").unwrap(),
)

///|
let result = @ai.generate_text(
  model,
  prompt="Explain MoonBit in three sentences.",
  instructions=@ai.Instructions::text("Keep the answer concise."),
)
```

The canonical MoonBit entry point is `generate_text`. The package also exposes
the AI SDK spelling `generateText` while the public surface is being aligned;
this is a naming convenience, not a promise to preserve an older Moonai API.

`generate_text`, `stream_text`, and `generate_object` share the `ai/prompt`
standardization boundary. `instructions` accepts only system messages and is
placed before regular messages. The regular `messages` input rejects the
system role by default; set `allow_system_in_messages=true` only when migrating
an existing history that already contains system messages.

## Streaming text

```moonbit nocheck
///|
let model = @openai.openai(
  "gpt-4.1-mini",
  api_key=@env.get_env_var("OPENAI_API_KEY").unwrap(),
)

///|
let result = @ai.stream_text(
  model,
  prompt="Explain MoonBit in three sentences.",
  on_event=event => {
    match event {
      @provider.V4TextDelta(delta~, ..) => @stdio.stdout.write(delta)
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

## Multi-step tools and sandbox

`generate_text` and `stream_text` share the same high-level `Tool` execution
layer. On every step, a tool's `description_resolver` receives its entry from
`tools_context` and the active `experimental_sandbox`; the resulting description
is sent to the model without replacing the executable tool. The same sandbox is
available to tool execution and streaming input callbacks.

`prepare_step` can override `tools_context` and `experimental_sandbox` for one
step. The following step starts from the outer values again, matching AI SDK's
step-local override semantics.

`provider_utils::SandboxSession` is the provider-neutral runtime contract. Its
`run` callback is required, while process spawning, streamed and buffered file
reads, and file writes are optional capabilities. Calling an unavailable
capability raises `UnsupportedFunctionalityError`; applications remain
responsible for supplying the concrete isolated runtime.

## Diagnostics, retries, and cancellation

Every normalized response exposes `request`, `response`, `provider_metadata`,
and typed `warnings`. Non-streaming response metadata includes the original
body; streaming bodies are not buffered, so use `include_raw_chunks=true` when
the raw SSE payloads are required.

Normalized `Usage` separates reasoning, cache-read, and cache-write accounting.
Providers report cache population through `cache_write_input_tokens`; usage
aggregation preserves that value across batched calls.

Invalid prompt shapes and message roles raise `InvalidPromptError`; invalid
setting values raise `InvalidArgumentError`. A successful HTTP response with
invalid protocol data raises `InvalidResponseDataError`. Asynchronous provider
operations such as video generation raise `ProviderTimeoutError` when polling
exceeds its deadline, keeping that condition separate from `APICallError`.

```moonbit nocheck
///|
let cancellation = @provider.CancellationToken::new()

///|
let retry_policy = @provider.RetryPolicy::new(
  max_retries=3,
  initial_delay_ms=200,
)

///|
let result = @ai.generate_text(
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

```moonbit nocheck
///|
let chat_model = @openai.openai_chat(
  "gpt-4.1-mini",
  api_key=@env.get_env_var("OPENAI_API_KEY").unwrap(),
)
```

The official provider exposes distinct `OpenAIResponsesModel` and
`OpenAIChatModel` implementations. Each has its own typed provider options and
model capability resolution for reasoning, role selection, and parameter
filtering; only protocol-level decoding and transport utilities are shared.

Organization and project routing can be configured once on the official
provider and is inherited by every selected model:

```moonbit nocheck
///|
let provider = @openai.create_openai(
  api_key~,
  organization="org-example",
  project="proj-example",
)
```

Explicit custom headers take precedence over API key, organization, and
project headers using case-insensitive header names.

Official Chat metadata includes accepted/rejected prediction token counts and
logprobs. Official Responses metadata includes the response id, service tier,
reasoning context, and logprobs. The same fields are accumulated for JSON and
SSE calls under the official provider's `provider_metadata` namespace.

## Anthropic Messages

```moonbit nocheck
///|
let model = @anthropic.anthropic(
  "claude-sonnet-4-20250514",
  api_key=@env.get_env_var("ANTHROPIC_API_KEY").unwrap(),
)

///|
let response = @ai.stream_text(
  model,
  prompt="Explain MoonBit in three sentences.",
  provider_options={
    "anthropic": {
      "thinking": { "type": "enabled", "budgetTokens": 4096 },
    },
  },
  on_event=event => {
    match event {
      @provider.V4TextDelta(delta~, ..) => @stdio.stdout.write(delta)
      @provider.V4ReasoningDelta(delta~, ..) => ()
      _ => ()
    }
  },
)
```

Anthropic supports native `generate_text` and `stream_text` requests through a
shared prepared-request layer. Standard `reasoning_effort` is mapped by model
capability to adaptive thinking and effort on newer Claude models, or to an
extended-thinking token budget on older models. Provider-specific overrides
remain available under `provider_options.anthropic`.

Messages accept text, URL/base64 images, and document file parts such as PDFs.
Audio parts are rejected before transport because the Messages API does not
accept them.

Provider-executed Anthropic tools use the shared `provider_utils` tool factory.
For example, the advisor tool has typed cache settings, validated empty input
and result schemas, deferred-result semantics, and automatic multi-turn replay:

```moonbit
///|
let advisor = @anthropic.advisor_20260301(
  model="claude-opus-4-8",
  max_uses=3,
  caching=@anthropic.AnthropicAdvisorCaching::new(
    ttl=@anthropic.AnthropicCacheOneHour,
  ),
)

///|
let result = @ai.generate_text(
  model,
  prompt="Implement the migration and ask the advisor to review the plan.",
  tools=@ai.tool_set([("advisor", advisor)]),
)
```

The `advisor-tool-2026-03-01` beta header is selected automatically. Plain,
redacted, and error advisor results are normalized on output and converted
back to Anthropic's wire format when the result history is sent again.

The application-executed `bash_20241022` and `bash_20250124` tools use the
current `SandboxSession::run` callback by default. A custom `execute` callback
takes precedence; `disable_default_execute=true` creates a non-executable tool,
corresponding to AI SDK's explicit `execute: null` configuration.

The provider also exposes `files()` and `skills()`. Files are uploaded through
Anthropic's Files API and returned as provider-neutral references. Skills
uploads support multiple `files[]`, an optional display title, the required
beta header, and a follow-up latest-version lookup for name and description
metadata. Both capabilities use the same authentication, custom headers, and
injectable `HttpTransport` as Messages.

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
let response = @ai.stream_text(
  deepseek,
  prompt="What is MoonBit?",
  reasoning_effort=@provider.High,
  on_event=event => {
    match event {
      @provider.V4TextDelta(delta~, ..) => @stdio.stdout.write(delta)
      _ => ()
    }
  },
)
```

Provider-wide query parameters apply to chat, completion, embedding, and image
endpoints. Enable structured outputs only when the compatible endpoint accepts
OpenAI's `json_schema` response format:

```moonbit nocheck
///|
let provider = @openai_compatible.create_openai_compatible(
  provider_name="example-gateway",
  base_url="https://example.com/v1",
  api_key~,
  query_params={ "api-version": "2026-08" },
  supports_structured_outputs=true,
)
```

`transform_request_body` can be supplied to the compatible provider factory to
apply gateway-specific changes after typed request preparation and immediately
before the HTTP transport sends the body.

Compatible providers can also replace `error_structure`, `metadata_extractor`,
and `convert_usage`. The error structure is shared by JSON/SSE transports and
the chat, completion, embedding, and image models. Metadata and usage hooks
customize complete and streaming chat responses; stream metadata extractors are
created per request so concurrent calls do not share state.

When the flag is disabled, a JSON Schema request falls back to `json_object`
and reports a typed warning instead of claiming schema enforcement.

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

The protocol package resolves namespaced options into typed values, produces a
prepared request with warnings, encodes the wire body, and then invokes the
transport. Custom providers can reuse that pipeline without inheriting the
official OpenAI model capability rules.

Its encoder supports URL-backed input files and multimodal tool results through
`Message::tool_parts`. Its decoder assembles text, refusal, reasoning, tool
argument deltas, terminal status, usage, and provider metadata for both complete
responses and interleaved SSE event streams.

## Provider options and reasoning

Use `reasoning_effort` for portable reasoning control. Adapters map it to their
wire format when possible and return a typed warning when a value is coerced or
the protocol cannot represent it.

Provider-specific request fields follow the AI SDK namespace convention. The
namespace is the camel-case form of `provider_name`; for example,
`example-gateway` becomes `exampleGateway`:

```moonbit nocheck
///|
let model = @openai_compatible.openai_compatible(
  provider_name="example-gateway",
  base_url="https://example.com/v1",
  model_id="example-model",
  api_key~,
)

///|
let response = @ai.generate_text(
  model,
  prompt="Explain the tradeoff.",
  provider_options={
    "exampleGateway": {
      "reasoningEffort": "high",
      "user": "user-1",
    },
  },
)
```

Provider options must be nested under their provider namespace. Fields owned
by the normalized request, such as `model`, `messages`, or `stream`, are
ignored and produce a compatibility warning.

## Structured output and multimodal input

```moonbit nocheck
///|
let object = @ai.generate_object(
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
let response = @ai.generate_text(
  model,
  messages=[
    @ai.ModelMessage::user_parts([
      @ai.ModelContentPart::text("Describe this image."),
      @ai.ModelContentPart::image_url("https://example.com/moon.png"),
    ]),
  ],
)
```

OpenAI-compatible Chat Completions accepts text, image, base64 audio, and
base64 PDF parts. Image URLs are passed through, `text/*` file URLs become text,
and PDF/audio file URLs are rejected before transport, matching AI SDK.
Official OpenAI Chat likewise passes through image URLs and rejects other file
URLs. Open Responses accepts image and file URLs, base64 files, and multimodal
tool result parts, but rejects audio input explicitly. Anthropic Messages
accepts text, image, and document parts and likewise rejects audio input.
`generate_object` requests JSON Schema output, parses the final JSON value, and
validates it with the shared `provider_utils` JSON Schema validator. Invalid
JSON and schema mismatches raise typed `NoObjectGeneratedError` values.

## Embeddings, completions, and images

```moonbit nocheck
///|
let provider = @openai.create_openai(api_key~)

///|
let vector = @ai.embed(
  provider.embedding("text-embedding-3-small"),
  "MoonBit",
)

///|
let completion = @ai.generate_text(
  provider.completion("gpt-3.5-turbo-instruct"),
  prompt="MoonBit is",
)

///|
let images = @ai.generate_image(
  provider.image("gpt-image-1"),
  "A precise MoonBit language logo",
  n=2,
  size="1024x1024",
)
```

`embed_many` and `generate_image` split requests at the model's per-call limit,
preserve result order, validate response counts, and accumulate usage. Embedding
models declare whether batches may run in parallel; pass `max_parallel_calls`
to cap concurrency when the provider supports it. Image payloads are tagged as
`ImageData::Base64` or `ImageData::Url`.

The snake-case provider selectors also have AI SDK-style camel-case aliases,
including `languageModel`, `embeddingModel`, `completionModel`, and
`imageModel`.

The initial API intentionally follows familiar AI SDK concepts without
requiring MoonBit code to copy TypeScript naming everywhere:

| Vercel AI SDK | moonai |
| --- | --- |
| `generateText({ model, prompt })` | `@ai.generate_text(model, prompt=...)` |
| `streamText({ model, prompt })` | `@ai.stream_text(model, prompt=...)` |
| `generateObject({ model, schema })` | `@ai.generate_object(model, schema, ...)` |
| `embed({ model, value })` | `@ai.embed(model, value)` |
| `embedMany({ model, values })` | `@ai.embed_many(model, values)` |
| `generateImage({ model, prompt })` | `@ai.generate_image(model, prompt)` |
| `openai("gpt-4.1")` | `@openai.openai("gpt-4.1", api_key=...)` |
| `createOpenAI({ baseURL })` | `@openai.create_openai(base_url=..., api_key=...)` |
| `createOpenAICompatible(...)` | `@openai_compatible.create_openai_compatible(...)` |
| `createOpenResponses(...)` | `@open_responses.create_open_responses(...)` |
| `anthropic("claude-sonnet-4-20250514")` | `@anthropic.anthropic("claude-sonnet-4-20250514", api_key=...)` |

## Design direction

The core library will remain provider-neutral. Provider-specific wire formats,
authentication, and options belong in adapter packages. Planned milestones
include richer generated content such as sources and files, image editing,
telemetry hooks, and higher-level agent orchestration.

The sandbox abstraction is already part of the shared tool boundary, but a
concrete sandbox runtime remains an application or runtime integration concern.
Higher-level agent workflows will build on these contracts rather than being
coupled to a provider protocol.

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
