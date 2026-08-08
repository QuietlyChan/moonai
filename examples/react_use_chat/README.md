# React useChat client

This client follows the Vercel AI SDK examples and talks directly to the
MoonBit Web Agent through `useChat` and `DefaultChatTransport`:

```ts
useChat({
  transport: new DefaultChatTransport({
    api: '/api/use-chat',
  }),
});
```

The MoonBit route emits the AI SDK UI message stream v1 SSE protocol. Text,
reasoning, dynamic tool input, tool output, step boundaries, final usage, and
regeneration are handled by the normal `useChat` state machine.

The client requires Node.js 22 or newer, matching the engine requirement of
the local AI SDK 7 source tree used as its reference.

Start the MoonBit backend from the repository root:

```shell
moon run examples/web_agent/backend
```

Then start this Vite client in a second terminal:

```shell
cd examples/react_use_chat
npm install
npm run dev
```

Open <http://127.0.0.1:5173>. Vite proxies `/api` to the MoonBit server at
<http://127.0.0.1:8080>, so no browser API key or CORS customization is needed.
