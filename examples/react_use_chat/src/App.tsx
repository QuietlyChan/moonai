import { useChat } from '@ai-sdk/react';
import {
  DefaultChatTransport,
  type DynamicToolUIPart,
  type UIMessage,
} from 'ai';
import {
  Bot,
  Calculator,
  CircleStop,
  CloudSun,
  Database,
  Eraser,
  RefreshCw,
  Search,
  Send,
  Sparkles,
  UserRound,
  Wrench,
} from 'lucide-react';
import { FormEvent, useState } from 'react';

type ChatMetadata = {
  provider?: string;
  model?: string;
  stepCount?: number;
  usage?: {
    inputTokens?: number;
    outputTokens?: number;
    totalTokens?: number;
  };
};

type MoonAIMessage = UIMessage<ChatMetadata>;

const transport = new DefaultChatTransport<MoonAIMessage>({
  api: '/api/use-chat',
});

const suggestions = [
  { icon: Calculator, text: 'Calculate 42 * 8 and explain the result.' },
  { icon: CloudSun, text: 'What is the weather in Hangzhou?' },
  { icon: Search, text: 'What does MoonAI support?' },
];

function formatValue(value: unknown) {
  if (typeof value === 'string') return value;
  return JSON.stringify(value, null, 2);
}

function toolStatus(part: DynamicToolUIPart) {
  switch (part.state) {
    case 'input-streaming':
      return 'Preparing input';
    case 'input-available':
      return 'Running';
    case 'output-available':
      return 'Complete';
    case 'output-error':
      return 'Failed';
    case 'output-denied':
      return 'Denied';
    case 'approval-requested':
      return 'Approval needed';
    case 'approval-responded':
      return 'Approval received';
  }
}

function ToolActivity({ part }: { part: DynamicToolUIPart }) {
  const hasOutput = part.state === 'output-available';
  const hasError = part.state === 'output-error';

  return (
    <section className="tool-activity" aria-label={`${part.toolName} tool`}>
      <div className="tool-heading">
        <span className="tool-icon" aria-hidden="true">
          <Wrench size={16} />
        </span>
        <div>
          <strong>{part.toolName}</strong>
          <span>{toolStatus(part)}</span>
        </div>
      </div>
      {'input' in part && part.input !== undefined && (
        <pre>{formatValue(part.input)}</pre>
      )}
      {hasOutput && <pre className="tool-output">{formatValue(part.output)}</pre>}
      {hasError && <p className="tool-error">{part.errorText}</p>}
    </section>
  );
}

function Message({ message }: { message: MoonAIMessage }) {
  const isUser = message.role === 'user';

  return (
    <article className={`message ${isUser ? 'message-user' : 'message-assistant'}`}>
      <div className="avatar" aria-hidden="true">
        {isUser ? <UserRound size={18} /> : <Bot size={18} />}
      </div>
      <div className="message-body">
        <div className="message-label">
          <strong>{isUser ? 'You' : 'MoonAI'}</strong>
          {!isUser && message.metadata?.model && (
            <span>{message.metadata.model}</span>
          )}
        </div>
        <div className="message-parts">
          {message.parts.map((part, index) => {
            switch (part.type) {
              case 'text':
                return (
                  <p className="message-text" key={index}>
                    {part.text}
                  </p>
                );
              case 'reasoning':
                return (
                  <details className="reasoning" key={index}>
                    <summary>Reasoning</summary>
                    <p>{part.text}</p>
                  </details>
                );
              case 'dynamic-tool':
                return <ToolActivity key={part.toolCallId} part={part} />;
              case 'step-start':
                return index > 0 ? <hr className="step-divider" key={index} /> : null;
              default:
                return null;
            }
          })}
        </div>
        {!isUser && message.metadata?.usage?.totalTokens !== undefined && (
          <div className="usage">
            <Database size={13} aria-hidden="true" />
            <span>{message.metadata.usage.totalTokens} tokens</span>
            {message.metadata.stepCount !== undefined && (
              <span>{message.metadata.stepCount} steps</span>
            )}
          </div>
        )}
      </div>
    </article>
  );
}

export default function App() {
  const [input, setInput] = useState('');
  const {
    messages,
    sendMessage,
    regenerate,
    stop,
    status,
    error,
    clearError,
    setMessages,
  } = useChat<MoonAIMessage>({ transport });
  const busy = status === 'submitted' || status === 'streaming';

  function submitText(text: string) {
    const value = text.trim();
    if (!value || busy) return;
    clearError();
    void sendMessage({ text: value });
    setInput('');
  }

  function handleSubmit(event: FormEvent) {
    event.preventDefault();
    submitText(input);
  }

  return (
    <div className="app-shell">
      <header className="topbar">
        <div className="brand">
          <span className="brand-mark" aria-hidden="true">
            <Sparkles size={18} />
          </span>
          <div>
            <strong>MoonAI</strong>
            <span>useChat workbench</span>
          </div>
        </div>
        <div className="header-actions">
          <span className={`connection connection-${status}`}>
            <i aria-hidden="true" />
            {busy ? 'Streaming' : status === 'error' ? 'Error' : 'Ready'}
          </span>
          {messages.length > 0 && (
            <>
              <button
                className="icon-button"
                type="button"
                onClick={() => void regenerate()}
                disabled={busy}
                aria-label="Regenerate response"
                title="Regenerate response"
              >
                <RefreshCw size={18} />
              </button>
              <button
                className="icon-button"
                type="button"
                onClick={() => setMessages([])}
                disabled={busy}
                aria-label="Clear conversation"
                title="Clear conversation"
              >
                <Eraser size={18} />
              </button>
            </>
          )}
        </div>
      </header>

      <main className="conversation" aria-live="polite">
        {messages.length === 0 ? (
          <div className="empty-state">
            <span className="empty-mark" aria-hidden="true">
              <Bot size={30} />
            </span>
            <h1>Start a conversation</h1>
            <div className="suggestions">
              {suggestions.map(({ icon: Icon, text }) => (
                <button key={text} type="button" onClick={() => submitText(text)}>
                  <Icon size={17} aria-hidden="true" />
                  <span>{text}</span>
                </button>
              ))}
            </div>
          </div>
        ) : (
          <div className="message-list">
            {messages.map(message => (
              <Message key={message.id} message={message} />
            ))}
          </div>
        )}
        {error && (
          <div className="error-banner" role="alert">
            <span>{error.message}</span>
            <button type="button" onClick={clearError}>
              Dismiss
            </button>
          </div>
        )}
      </main>

      <footer className="composer-wrap">
        <form className="composer" onSubmit={handleSubmit}>
          <textarea
            value={input}
            onChange={event => setInput(event.target.value)}
            onKeyDown={event => {
              if (event.key === 'Enter' && !event.shiftKey) {
                event.preventDefault();
                submitText(input);
              }
            }}
            placeholder="Message MoonAI"
            rows={1}
            disabled={busy}
            aria-label="Message MoonAI"
          />
          {busy ? (
            <button
              className="submit-button stop-button"
              type="button"
              onClick={() => void stop()}
              aria-label="Stop response"
              title="Stop response"
            >
              <CircleStop size={19} />
            </button>
          ) : (
            <button
              className="submit-button"
              type="submit"
              disabled={!input.trim()}
              aria-label="Send message"
              title="Send message"
            >
              <Send size={18} />
            </button>
          )}
        </form>
      </footer>
    </div>
  );
}
