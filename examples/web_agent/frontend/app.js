const elements = {
  activityCount: document.querySelector("#activityCount"),
  activityFeed: document.querySelector("#activityFeed"),
  characterCount: document.querySelector("#characterCount"),
  clearConversation: document.querySelector("#clearConversation"),
  composer: document.querySelector("#composer"),
  connectionLabel: document.querySelector("#connectionLabel"),
  connectionStatus: document.querySelector("#connectionStatus"),
  emptyActivity: document.querySelector("#emptyActivity"),
  inputTokens: document.querySelector("#inputTokens"),
  messageInput: document.querySelector("#messageInput"),
  modelValue: document.querySelector("#modelValue"),
  outputTokens: document.querySelector("#outputTokens"),
  promptPreset: document.querySelector("#promptPreset"),
  providerValue: document.querySelector("#providerValue"),
  sendButton: document.querySelector("#sendButton"),
  stepCount: document.querySelector("#stepCount"),
  stopButton: document.querySelector("#stopButton"),
  totalTokens: document.querySelector("#totalTokens"),
  transcript: document.querySelector("#transcript"),
  turnStatus: document.querySelector("#turnStatus"),
};

const state = {
  activities: new Map(),
  controller: null,
  generating: false,
  messages: [],
};

function refreshIcons(root = document) {
  if (window.lucide) {
    window.lucide.createIcons({ root });
  }
}

function formatTime() {
  return new Intl.DateTimeFormat(undefined, {
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date());
}

function scrollTranscript() {
  requestAnimationFrame(() => {
    elements.transcript.scrollTop = elements.transcript.scrollHeight;
  });
}

function createMessage(role, text = "") {
  const article = document.createElement("article");
  article.className = `message ${role}`;

  const avatar = document.createElement("div");
  avatar.className = "message-avatar";
  avatar.setAttribute("aria-hidden", "true");
  const icon = document.createElement("i");
  icon.dataset.lucide = role === "user" ? "user" : "sparkles";
  avatar.append(icon);

  const body = document.createElement("div");
  body.className = "message-body";
  const meta = document.createElement("div");
  meta.className = "message-meta";
  meta.textContent = `${role === "user" ? "You" : "MoonAI"} · ${formatTime()}`;
  const content = document.createElement("p");
  content.className = "message-text";
  content.textContent = text;
  body.append(meta, content);
  article.append(avatar, body);
  elements.transcript.append(article);
  refreshIcons(article);
  scrollTranscript();
  return { article, content, meta, body };
}

function renderWelcome() {
  elements.transcript.replaceChildren();
  createMessage("assistant", "MoonAI is online. What are we working on?");
}

function updateComposer() {
  const length = elements.messageInput.value.length;
  elements.characterCount.textContent = `${length} / 8000`;
  elements.sendButton.disabled = state.generating || length === 0;
  elements.messageInput.style.height = "auto";
  elements.messageInput.style.height = `${Math.min(elements.messageInput.scrollHeight, 152)}px`;
}

function setGenerating(value) {
  state.generating = value;
  elements.transcript.setAttribute("aria-busy", String(value));
  elements.messageInput.disabled = value;
  elements.promptPreset.disabled = value;
  elements.stopButton.hidden = !value;
  elements.sendButton.hidden = value;
  elements.turnStatus.textContent = value ? "Running" : "Ready";
  updateComposer();
}

function setConnection(stateName, label) {
  elements.connectionStatus.dataset.state = stateName;
  elements.connectionLabel.textContent = label;
}

function updateRuntime(provider, model) {
  elements.providerValue.textContent = provider || "Unknown";
  elements.modelValue.textContent = model || "Unknown";
}

function updateUsage(usage = {}, steps) {
  elements.inputTokens.textContent = usage.inputTokens ?? 0;
  elements.outputTokens.textContent = usage.outputTokens ?? 0;
  elements.totalTokens.textContent = usage.totalTokens ?? 0;
  if (typeof steps === "number") {
    elements.stepCount.textContent = steps;
  }
}

function formatPayload(payload) {
  if (payload === undefined || payload === null || payload === "") {
    return "";
  }
  if (typeof payload === "string") {
    try {
      return JSON.stringify(JSON.parse(payload), null, 2);
    } catch {
      return payload;
    }
  }
  return JSON.stringify(payload, null, 2);
}

function resetActivity() {
  state.activities.clear();
  elements.activityFeed.replaceChildren(elements.emptyActivity);
  elements.emptyActivity.hidden = false;
  elements.activityCount.textContent = "0";
}

function activityFor(event) {
  const id = event.toolCallId || `${event.toolName || "tool"}-${state.activities.size + 1}`;
  if (state.activities.has(id)) {
    return state.activities.get(id);
  }

  elements.emptyActivity.hidden = true;
  const item = document.createElement("article");
  item.className = "activity-item";
  item.dataset.state = "queued";
  const title = document.createElement("div");
  title.className = "activity-title";
  const icon = document.createElement("i");
  icon.dataset.lucide = "terminal";
  const name = document.createElement("strong");
  name.textContent = event.toolName || "Tool";
  const status = document.createElement("span");
  status.className = "activity-state";
  status.textContent = "Queued";
  const payload = document.createElement("pre");
  payload.className = "activity-payload";
  payload.hidden = true;
  title.append(icon, name, status);
  item.append(title, payload);
  elements.activityFeed.append(item);
  const activity = { id, item, name, status, payload, inputText: "" };
  state.activities.set(id, activity);
  elements.activityCount.textContent = String(state.activities.size);
  refreshIcons(item);
  return activity;
}

function updateActivity(event) {
  const activity = activityFor(event);
  if (event.toolName) {
    activity.name.textContent = event.toolName;
  }

  switch (event.type) {
    case "tool-input-start":
      activity.item.dataset.state = "running";
      activity.status.textContent = "Preparing";
      break;
    case "tool-input-delta":
      activity.inputText += event.delta || "";
      activity.payload.textContent = formatPayload(activity.inputText);
      activity.payload.hidden = false;
      break;
    case "tool-call":
      activity.item.dataset.state = "running";
      activity.status.textContent = "Requested";
      activity.payload.textContent = formatPayload(event.inputText);
      activity.payload.hidden = !activity.payload.textContent;
      break;
    case "tool-execution-start":
      activity.item.dataset.state = "running";
      activity.status.textContent = "Running";
      activity.payload.textContent = formatPayload(event.payload);
      activity.payload.hidden = !activity.payload.textContent;
      break;
    case "tool-execution-result":
    case "provider-tool-result":
      activity.item.dataset.state = event.isError ? "error" : "complete";
      activity.status.textContent = event.isError ? "Failed" : "Complete";
      activity.payload.textContent = formatPayload(event.payload ?? event.output);
      activity.payload.hidden = false;
      break;
    default:
      break;
  }
  elements.activityFeed.scrollTop = elements.activityFeed.scrollHeight;
}

function appendReasoning(message, delta) {
  let details = message.body.querySelector(".reasoning");
  if (!details) {
    details = document.createElement("details");
    details.className = "reasoning";
    details.open = true;
    const summary = document.createElement("summary");
    summary.textContent = "Reasoning";
    const text = document.createElement("p");
    text.className = "reasoning-text";
    details.append(summary, text);
    message.body.append(details);
  }
  details.querySelector(".reasoning-text").textContent += delta;
}

function processEvent(event, assistant) {
  switch (event.type) {
    case "metadata":
      updateRuntime(event.provider, event.model);
      assistant.meta.textContent = `MoonAI · ${event.provider} / ${event.model}`;
      break;
    case "text-delta":
      assistant.content.textContent += event.delta || "";
      scrollTranscript();
      break;
    case "reasoning-delta":
      appendReasoning(assistant, event.delta || "");
      scrollTranscript();
      break;
    case "tool-input-start":
    case "tool-input-delta":
    case "tool-input-end":
    case "tool-call":
    case "tool-execution-start":
    case "tool-execution-result":
    case "provider-tool-result":
      updateActivity(event);
      break;
    case "step-finish":
      updateUsage(event.usage);
      elements.stepCount.textContent = String(Number(elements.stepCount.textContent) + 1);
      break;
    case "provider-error":
      throw new Error(event.message || "Provider stream error");
    case "error":
      throw new Error(event.message || "Agent request failed");
    case "finish":
      if (!assistant.content.textContent && event.text) {
        assistant.content.textContent = event.text;
      }
      updateUsage(event.usage, event.stepCount);
      return event;
    default:
      break;
  }
  return null;
}

async function readEventStream(response, assistant) {
  if (!response.ok) {
    const body = await response.text();
    try {
      const parsed = JSON.parse(body);
      throw new Error(parsed.error || `Request failed with ${response.status}`);
    } catch (error) {
      if (error instanceof SyntaxError) {
        throw new Error(body || `Request failed with ${response.status}`);
      }
      throw error;
    }
  }
  if (!response.body) {
    throw new Error("Streaming response body is unavailable.");
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let finishEvent = null;

  while (true) {
    const { value, done } = await reader.read();
    buffer += decoder.decode(value || new Uint8Array(), { stream: !done });
    const lines = buffer.split("\n");
    buffer = lines.pop() || "";
    for (const line of lines) {
      if (!line.trim()) continue;
      finishEvent = processEvent(JSON.parse(line), assistant) || finishEvent;
    }
    if (done) break;
  }
  if (buffer.trim()) {
    finishEvent = processEvent(JSON.parse(buffer), assistant) || finishEvent;
  }
  return finishEvent;
}

async function submitMessage(event) {
  event.preventDefault();
  const text = elements.messageInput.value.trim();
  if (!text || state.generating) return;

  createMessage("user", text);
  state.messages.push({ role: "user", content: text });
  elements.messageInput.value = "";
  elements.promptPreset.value = "";
  resetActivity();
  updateUsage({}, 0);
  const assistant = createMessage("assistant");
  assistant.article.classList.add("streaming");
  state.controller = new AbortController();
  setGenerating(true);

  try {
    const response = await fetch("/api/chat/stream", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ messages: state.messages.slice(-24) }),
      signal: state.controller.signal,
    });
    const finished = await readEventStream(response, assistant);
    const finalText = finished?.text || assistant.content.textContent;
    if (!finalText) {
      throw new Error("The model completed without returning text.");
    }
    assistant.content.textContent = finalText;
    state.messages.push({ role: "assistant", content: finalText });
    setConnection("online", "Connected");
  } catch (error) {
    const stopped = error.name === "AbortError";
    assistant.content.textContent = stopped
      ? assistant.content.textContent || "Generation stopped."
      : `Request failed: ${error.message}`;
    assistant.article.classList.add("error");
    if (!stopped) setConnection("offline", "Request error");
  } finally {
    assistant.article.classList.remove("streaming");
    state.controller = null;
    setGenerating(false);
    elements.messageInput.focus();
    scrollTranscript();
  }
}

function clearConversation() {
  state.controller?.abort();
  state.messages = [];
  resetActivity();
  updateUsage({}, 0);
  renderWelcome();
  elements.messageInput.value = "";
  elements.promptPreset.value = "";
  updateComposer();
  elements.messageInput.focus();
}

async function loadHealth() {
  try {
    const response = await fetch("/api/health", { cache: "no-store" });
    if (!response.ok) throw new Error(`Health check failed with ${response.status}`);
    const health = await response.json();
    updateRuntime(health.provider, health.model);
    setConnection("online", health.demo ? "Demo online" : "Connected");
  } catch {
    updateRuntime("Unavailable", "Unavailable");
    setConnection("offline", "Server offline");
  }
}

elements.composer.addEventListener("submit", submitMessage);
elements.messageInput.addEventListener("input", updateComposer);
elements.messageInput.addEventListener("keydown", (event) => {
  if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
    event.preventDefault();
    elements.composer.requestSubmit();
  }
});
elements.promptPreset.addEventListener("change", () => {
  if (elements.promptPreset.value) {
    elements.messageInput.value = elements.promptPreset.value;
    updateComposer();
    elements.messageInput.focus();
  }
});
elements.stopButton.addEventListener("click", () => state.controller?.abort());
elements.clearConversation.addEventListener("click", clearConversation);

renderWelcome();
refreshIcons();
updateComposer();
loadHealth();
