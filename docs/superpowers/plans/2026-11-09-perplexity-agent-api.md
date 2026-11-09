# Perplexity Agent API Implementation Plan

> **For agentic workers:** Execute the checked steps inline and validate the provider through MoonBit tests.

**Goal:** Migrate Moonai's Perplexity language model from `/chat/completions` to the current `/v1/agent` API while preserving its V4 model factory and embedding endpoint.

**Architecture:** Keep Perplexity's Agent-specific request, prompt, response, and stream mapping inside `src/perplexity`; use an explicit provider decoder for both standard Responses-style events and Perplexity reasoning/search event families so terminal metadata and tool-call precedence stay provider-correct. Leave embedding behavior on `/v1/embeddings`.

**Tech Stack:** MoonBit, provider V4 contract, `provider_utils` HTTP/SSE transport, in-process HTTP integration tests.

---

### Task 1: Define Agent request and prompt conversion

**Files:**
- Create: `src/perplexity/agent_request.mbt`
- Modify: `src/perplexity/options.mbt`
- Modify: `src/perplexity/moon.pkg`
- Test: `src/perplexity/perplexity_wbtest.mbt`

- [x] Select documented Agent presets (`fast`, `low`, `medium`, `high`, `xhigh`); pass other model IDs via `model`.
- [x] Convert V4 system/user/assistant/tool messages to Agent `input`, including text, image URL/data, tool calls, and tool results; raise `UnsupportedFunctionalityError` for unsupported file/reference content.
- [x] Encode native provider options, AI SDK function tools, JSON schema output, sampling fields, reasoning effort, and `toolChoice: none` (`tools` omitted, `max_tool_calls: 0`).
- [x] Add deterministic tests for model selection, request fields, tool and response-format conversion, and unsupported parts.

### Task 2: Decode Agent responses and metadata

**Files:**
- Create: `src/perplexity/agent_response.mbt`
- Create: `src/perplexity/agent_validation.mbt`
- Modify: `src/perplexity/shared.mbt`
- Modify: `src/perplexity/chat.mbt`
- Test: `src/perplexity/perplexity_wbtest.mbt`

- [x] Map Agent output messages, annotations, web search results, fetched URL results, and function calls to V4 content while preserving source order and deduplicating identical URLs.
- [x] Map status/incomplete reasons to V4 finish reason, preserve response metadata, and map usage/cache/reasoning/cost/tool-call details.
- [x] Raise structured API errors for `failed` responses and invalid required fields.
- [x] Cover representative success, error, partial/unknown native output, finish-reason, and metadata cases with fixture-shaped JSON.

### Task 3: Decode Agent event streams

**Files:**
- Create: `src/perplexity/agent_stream.mbt`
- Delete: `src/perplexity/stream.mbt` (replaced by the Agent decoder)
- Modify: `src/perplexity/moon.pkg`
- Test: `src/perplexity/perplexity_wbtest.mbt`

- [x] Decode standard Responses-style text, function-call, response-metadata, usage, and terminal events in the Perplexity stream state machine.
- [x] Add Perplexity handling for reasoning thought/search/fetch events, output-item search/fetch results, citations, duplicate-suppressed sources, and terminal Agent metadata.
- [x] Preserve raw chunks on request, expose malformed stream chunks as `V4Error`, report interrupted EOF, and always attach final usage/provider metadata.
- [x] Add synthetic SSE tests for text, reasoning, function calls, sources, terminal metadata, malformed chunks, and an incomplete stream.

### Task 4: Verify the transport boundary and package

**Files:**
- Modify: `src/perplexity/perplexity_test.mbt`
- Modify as generated: `src/perplexity/pkg.generated.mbti`
- Modify: `docs/superpowers/plans/2026-11-09-perplexity-agent-api.md`

- [x] Add a local HTTP integration test asserting `POST /v1/agent`, the Agent JSON body, auth/header forwarding, response text, and metadata.
- [x] Confirm the embedding implementation still uses `/v1/embeddings`.
- [x] Run `moon info`, `moon fmt`, `moon fmt --check`, `moon check -d`, focused Perplexity tests, and `git diff --check`.
- [x] Review the generated interface and final diff; leave changes uncommitted unless separately requested.

The first full `moon test` run found one pre-existing assertion mismatch outside this package: `provider_utils/download_test.mbt` expected `http://` for a fixture with an `https://` redirect. The assertion was corrected to match its fixture without changing the download security logic.

Moonai's shared V4 enum does not yet contain an `interrupted` member. Until that contract is expanded, a stream missing its Agent terminal event reports `unified: other` and `raw: interrupted` rather than claiming successful completion.

## Final Verification

- Global executable: `C:\Users\Administrator\.moon\bin\moon.exe`, version `0.1.20261104`.
- `moon info`, `moon fmt`, `moon fmt --check`, `moon check -d`, and `git diff --check`: passed.
- Focused Perplexity tests: 17 passed, including local HTTP generation/SSE/embedding checks.
- Full `moon test`: 1175 passed, 0 failed.
- Generated public interfaces unchanged; no commit or push performed.
- No live Perplexity API calls were made; the protocol and transport checks use deterministic local responses.
