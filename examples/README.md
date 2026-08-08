# MoonAI examples

This workspace module contains runnable MoonBit examples for the MoonAI SDK.
Every example defaults to the local `demo` provider, so the complete chat and
tool-calling flows work without an API key or network request.

## Examples

| Directory | What it demonstrates |
| --- | --- |
| `basic_chat` | Provider-neutral `stream_text` and normalized text events |
| `tool_calling` | Multi-step generation, executable MoonBit tools, and usage aggregation |
| `web_agent` | MoonBit HTTP APIs, embedded browser chat, NDJSON, AI SDK v1 SSE, and tool activity |
| `react_use_chat` | Vercel AI SDK `useChat` connected to the MoonBit SSE endpoint |
| `shared` | Environment configuration, deterministic demo model, and reusable tools |
| `embed_assets` | Build-time generator for the standalone Web Agent binary |

Run the CLI examples from the repository root:

```shell
moon run examples/basic_chat -- "Explain MoonAI briefly."
moon run examples/tool_calling -- "Calculate 42 * 8."
```

Start the browser agent at <http://127.0.0.1:8080>:

```shell
moon run examples/web_agent/backend
```

The default Web frontend is plain HTML, CSS, and JavaScript served by the
MoonBit backend. It uses the custom NDJSON stream and has no separate build or
package-install step.

## React useChat client

The MoonBit server also implements the Vercel AI SDK UI message stream v1
protocol at `POST /api/use-chat`. Start the backend, then run the React client:

```shell
cd examples/react_use_chat
npm install
npm run dev
```

Open <http://127.0.0.1:5173>. Its Vite proxy forwards `/api/use-chat` to the
MoonBit process. The client uses the same pattern as the local Vercel AI SDK
`next` and `next-agent` examples:

```ts
useChat({
  transport: new DefaultChatTransport({ api: '/api/use-chat' }),
});
```

Text, reasoning, multi-step boundaries, dynamic tool input, tool output,
regeneration, and final metadata are handled by the standard `useChat` state
machine.

## Standalone binary

Frontend assets are generated into MoonBit source and compiled into the native
server. On Windows, build a redistributable executable with:

```powershell
.\examples\build_standalone.ps1
```

The script writes `dist/moonai-agent.exe`. Copy that file to an empty directory
and run it; no adjacent frontend files, Node.js runtime, or API key are needed
for the default demo provider. During development, regenerate embedded assets
directly with:

```shell
moon run examples/embed_assets
```

## Provider configuration

`MOONAI_PROVIDER` selects the provider. The examples accept these values:

| Value | Default model | Provider-specific key variable |
| --- | --- | --- |
| `demo` | `moonai-demo` | None |
| `openai` | `gpt-4.1-mini` | `OPENAI_API_KEY` |
| `anthropic` | `claude-sonnet-4-5` | `ANTHROPIC_API_KEY` |
| `deepseek` | `deepseek-chat` | `DEEPSEEK_API_KEY` |
| `alibaba` | `qwen-plus` | `ALIBABA_API_KEY` |
| `minimax` | `MiniMax-M2.1` | `MINIMAX_API_KEY` |
| `openai-compatible` | `local-model` | Configure `MOONAI_API_KEY` when required |
| `open-responses` | `local-model` | Configure `MOONAI_API_KEY` when required |

All live providers support the common overrides below:

| Variable | Purpose |
| --- | --- |
| `MOONAI_MODEL` | Override the default model identifier |
| `MOONAI_API_KEY` | Override the provider-specific API key variable |
| `MOONAI_BASE_URL` | Override a bundled provider URL; required for compatible providers |

PowerShell example:

```powershell
$env:MOONAI_PROVIDER = "openai"
$env:OPENAI_API_KEY = "your-api-key"
$env:MOONAI_MODEL = "gpt-4.1-mini"
moon run examples/basic_chat -- "Write a MoonBit haiku."
```

POSIX shell example:

```shell
MOONAI_PROVIDER=openai \
OPENAI_API_KEY=your-api-key \
MOONAI_MODEL=gpt-4.1-mini \
moon run examples/basic_chat -- "Write a MoonBit haiku."
```

API keys remain in the MoonBit process. The Web backend only exposes the
selected provider and model to the browser.

## Bundled tools

The CLI agent and Web agent share three deterministic MoonBit tools:

- `calculator` performs add, subtract, multiply, and divide operations.
- `get_weather` returns a local weather fixture for a requested city.
- `search_moonai` searches a small bundled SDK knowledge fixture.

`stream_text` runs them through MoonAI's normal multi-step loop. They are not
special-cased by the UI or demo model after the provider emits a tool call.

## Validation

From the repository root, the workspace validates the SDK and examples
together:

```shell
moon info
moon fmt --check
moon check
moon test
cd examples/react_use_chat && npm run build
```
