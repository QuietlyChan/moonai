# AI SDK 7 Parity Implementation Plan

> **For agentic workers:** Execute the checked steps inline and verify each package boundary before moving to the next.

**Goal:** Bring Moonai's existing provider implementations closer to upstream AI SDK 7.0.165 where the upstream protocol behavior has a direct Moonai equivalent.

**Architecture:** Compare the local `D:\code\ai` checkout with Moonai's existing provider packages. Port behavior to the existing MoonBit boundaries, add package-local regression coverage, and record upstream-only features that need a protocol/API design rather than silently mixing them into an incompatible endpoint.

**Tech Stack:** MoonBit, `moon info`, `moon fmt`, `moon fmt --check`, `moon check -d`, and `moon test`.

---

### Task 1: Reconcile the tracked upstream changes

**Files:**
- Inspect only: `D:\code\ai\packages\...`
- Modify: existing Moonai provider and provider-utils files listed below.

- [x] Confirm the upstream checkout is on AI SDK 7.0.165 commit `0f3a85f92d` and clean.
- [x] Confirm Moonai starts on `main` at `bde5dda`, equal to `origin/main`.
- [x] Keep edits scoped to Moonai; do not modify either repository's history.
- [x] Compare the tracked changes for OpenAI, OpenAI-compatible, Cohere, Perplexity, Google, media detection, provider options, and request metadata.

### Task 2: Fix refusal handling in existing Chat APIs

**Files:**
- Modify: `src/openai/chat_decoder.mbt`
- Modify: `src/openai/chat_decoder_wbtest.mbt`
- Modify: `src/openai_compatible/decoder.mbt`
- Modify: `src/openai_compatible/response.mbt`
- Modify: `src/openai_compatible/decoder_wbtest.mbt`
- Modify: `src/openai/metadata.mbt`

- [x] Surface non-empty response refusal text as text content.
- [x] Emit refusal stream deltas as text and combine refusal logprobs with content logprobs.
- [x] Retain a refusal-seen flag in the official OpenAI stream decoder and map a final raw `stop` to `content-filter`, regardless of which SSE chunk contains the finish reason; preserve tool-call finish reasons.
- [x] Keep the OpenAI-compatible decoder's refusal-seen state and raw finish reason.
- [x] Run the refusal-focused OpenAI and OpenAI-compatible test filters.

### Task 3: Resolve namespaced provider options by precedence

**Files:**
- Modify: `src/provider_utils/provider_options.mbt`
- Modify: `src/provider_utils/provider_utils_test.mbt`
- Modify: `src/openai/provider_options.mbt`
- Modify: `src/openai/typed_provider_options_wbtest.mbt`
- Modify: `src/openai/completion_v4_request_wbtest.mbt`

- [x] Add ordered namespace merge support to provider-utils.
- [x] Keep OpenAI-compatible raw/camel namespace merging on its existing resolver path.
- [x] Merge `openai` then `azure` options for Azure Chat requests, with Azure values winning.
- [x] Merge `openai` then the selected provider namespace for OpenAI legacy-completion requests, with the selected provider values winning.
- [x] Preserve the current single-namespace behavior for ordinary OpenAI Chat, Responses, image, embedding, speech, and transcription requests.
- [x] Add request-body and parser assertions for the new Azure and completion precedence paths.

### Task 4: Keep supported provider behavior synchronized

**Files:**
- Modify: `src/cohere/shared.mbt`
- Modify: `src/cohere/chat.mbt`
- Modify: `src/cohere/stream.mbt`
- Modify: `src/cohere/cohere_wbtest.mbt`
- Modify: `src/perplexity/chat.mbt`
- Modify: `src/perplexity/perplexity_wbtest.mbt`

- [x] Accept Cohere v2 chat `id`, retaining `generation_id` as a compatibility fallback.
- [x] Accept a Cohere reranking response with results and no `meta` object.
- [x] Map document citations to source content with their title and citation metadata; tolerate missing or tool-only citations in both generate and stream paths.
- [x] Keep absent Cohere token counts absent and preserve cached-token accounting instead of reporting billed units as tokens.
- [x] For Perplexity's existing Chat Completions endpoint, suppress provider-option tool declarations and ensure an explicit `toolChoice: none` cannot be overridden by the option layer.
- [x] Test those request/response cases through the existing provider methods and request preparation.

### Task 5: Sanitize request diagnostics before they leave text workflows

**Files:**
- Modify: `src/provider_utils/url.mbt`
- Modify: `src/provider_utils/http_json.mbt`
- Modify: `src/ai/generate_text/generate_text.mbt`
- Modify: `src/ai/generate_text/stream_text.mbt`
- Modify: `src/provider_utils/provider_utils_test.mbt`

- [x] Add HTTP-origin sanitization that removes credentials, paths, queries, and fragments from a request metadata URL.
- [x] Apply sanitization within `generate_text` and `stream_text` provider-call results before telemetry callers receive them.
- [x] Keep ordinary request headers/body intact while sanitizing request metadata, covered by the local HTTP integration test.

### Task 6: Map OpenAI Responses refusal output

**Files:**
- Modify: `src/openai/responses_decoder.mbt`
- Modify: `src/openai/responses_decoder_wbtest.mbt`
- Modify: `src/openai/responses_stream_runtime.mbt`
- Modify: `src/openai/responses_stream_runtime_wbtest.mbt`

- [x] Surface Responses refusal content as text and map a completed refusal to `content-filter`.
- [x] Preserve `tool-calls` as the finish reason when client-side calls accompany refusal text.
- [x] Accumulate refusal stream events and map the terminal stop to `content-filter`.

### Task 7: Finish interface generation, formatting, and validation

**Files:**
- Modify as generated: `src/**/pkg.generated.mbti`

- [x] Run `moon info`.
- [x] Run `moon fmt` and verify `moon fmt --check` passes.
- [x] Run `moon check -d` and focused `moon test` filters on the available native target.
- [x] Run the selected provider package tests; inspect `.mbti` changes and review final `git status`.
- [x] Leave the changes uncommitted and unpushed.

### Tracked upstream items not included in this pass

- `32dc1d2d17` and `26fc2a998f`: Moonai Google Chat does not yet serialize supported provider-defined Google tools or stream Google function calls, so the Google request/stream contract needs its own implementation before these fixes can be represented faithfully.
- `7772d0ca0f`: AI SDK Perplexity now uses its Agent API, while Moonai's provider still targets Chat Completions; do not send Agent-only `max_tool_calls` or Agent tool arrays to the Chat endpoint.
- `cab9c1f452`: Moonai's media detection uses explicit pattern matching rather than JavaScript object property lookup, so the inherited-property issue has no corresponding implementation.
- `6400cf8b88`: The upstream change includes Azure routing, legacy aliases, and many unrelated media APIs. This pass ports only the existing Moonai OpenAI Chat and completion request paths; it does not claim Azure provider parity.
- Anthropic inline provider tools and other provider/API features require a separate gap audit against the exact corresponding Moonai protocol implementation.
