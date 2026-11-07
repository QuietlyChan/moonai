/* MoonAI landing interactions: scroll reveal, copy install command, mock agent demo. */

(() => {
  "use strict";

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- scroll reveal ---------- */

  const revealItems = Array.from(document.querySelectorAll(".reveal"));
  if (reduceMotion || !("IntersectionObserver" in window)) {
    revealItems.forEach((item) => item.classList.add("is-visible"));
  } else {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.1 },
    );
    revealItems.forEach((item) => observer.observe(item));
  }

  /* ---------- copy install command ---------- */

  const installButton = document.getElementById("installCommand");
  const installCopy = document.getElementById("installCopy");
  if (installButton && installCopy) {
    installButton.addEventListener("click", async () => {
      const command = "moon add QuietlyChan/moonai@0.2.0";
      try {
        await navigator.clipboard.writeText(command);
        installCopy.textContent = "已复制";
      } catch {
        installCopy.textContent = "请手动复制";
      }
      window.setTimeout(() => {
        installCopy.textContent = "复制";
      }, 1600);
    });
  }

  /* ---------- mock demo ---------- */

  const transcript = document.getElementById("demoTranscript");
  const emptyState = document.getElementById("demoEmpty");
  const composer = document.getElementById("demoComposer");
  const input = document.getElementById("demoInput");
  const sendButton = document.getElementById("demoSend");
  const status = document.getElementById("demoStatus");
  const activity = document.getElementById("demoActivity");
  const suggestions = document.getElementById("demoSuggestions");
  const usageInput = document.getElementById("usageInput");
  const usageOutput = document.getElementById("usageOutput");
  const usageSteps = document.getElementById("usageSteps");

  if (!transcript || !composer || !input || !sendButton) {
    return;
  }

  let busy = false;

  const element = (tag, className, text) => {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  };

  const sleep = (ms) => new Promise((resolve) => window.setTimeout(resolve, ms));

  const wait = (ms) => sleep(reduceMotion ? Math.min(ms, 40) : ms);

  const clearEmptyState = () => {
    if (emptyState && emptyState.parentNode) {
      emptyState.remove();
    }
  };

  const scrollTranscript = () => {
    transcript.scrollTop = transcript.scrollHeight;
  };

  const setStatus = (label, state) => {
    if (!status) return;
    status.textContent = label;
    if (state) {
      status.dataset.state = state;
    } else {
      delete status.dataset.state;
    }
  };

  const addUserMessage = (text) => {
    const wrap = element("div", "msg msg-user");
    wrap.appendChild(element("span", "msg-role", "You"));
    wrap.appendChild(element("p", "msg-body", text));
    transcript.appendChild(wrap);
    scrollTranscript();
  };

  const addAssistantMessage = () => {
    const wrap = element("div", "msg msg-assistant");
    wrap.appendChild(element("span", "msg-role", "MoonAI"));
    const body = element("p", "msg-body");
    const caret = element("span", "caret");
    caret.setAttribute("aria-hidden", "true");
    body.appendChild(caret);
    wrap.appendChild(body);
    transcript.appendChild(wrap);
    scrollTranscript();
    return { body, caret };
  };

  const addActivityRow = (label) => {
    if (!activity) return null;
    const empty = activity.querySelector(".demo-activity-empty");
    if (empty) empty.remove();
    const row = element("div", "activity-row");
    row.dataset.state = "running";
    const dot = element("span", "activity-dot");
    dot.setAttribute("aria-hidden", "true");
    row.appendChild(dot);
    row.appendChild(element("span", "", label));
    activity.appendChild(row);
    activity.scrollTop = activity.scrollHeight;
    return row;
  };

  const setUsage = (inputTokens, outputTokens, steps) => {
    if (usageInput) usageInput.textContent = String(inputTokens);
    if (usageOutput) usageOutput.textContent = String(outputTokens);
    if (usageSteps) usageSteps.textContent = String(steps);
  };

  const typeText = async (message, text) => {
    const characters = Array.from(text);
    for (const character of characters) {
      message.caret.before(document.createTextNode(character));
      if (!reduceMotion && Math.random() > 0.55) {
        transcript.scrollTop = transcript.scrollHeight;
      }
      await wait(14);
    }
  };

  const runTool = async (bodyNode, spec) => {
    const card = element("div", "tool-card");
    const head = element("div", "tool-card-head");
    head.appendChild(element("span", "", spec.name));
    const state = element("span", "tool-card-state", "input streaming");
    state.dataset.state = "running";
    head.appendChild(state);
    card.appendChild(head);

    const args = element("code", "", "");
    card.appendChild(args);
    const result = element("p", "tool-card-result", "");
    card.appendChild(result);
    bodyNode.parentNode.insertBefore(card, bodyNode);
    scrollTranscript();

    const row = addActivityRow(spec.name);

    const inputText = JSON.stringify(spec.input);
    for (let i = 0; i < inputText.length; i += 3) {
      args.textContent = inputText.slice(0, i + 3);
      await wait(26);
    }
    args.textContent = inputText;

    state.textContent = "running";
    card.style.borderLeftColor = "var(--amber)";
    if (row) row.dataset.state = "running";

    await wait(420);

    state.textContent = "done";
    state.dataset.state = "done";
    result.textContent = spec.result;
    if (row) row.dataset.state = "done";
    card.style.borderLeftColor = "var(--ok)";
    scrollTranscript();

    await wait(180);
  };

  const normalize = (text) => text.toLowerCase();

  const planFor = (prompt) => {
    const text = normalize(prompt);

    if (/(42|计算|calculate|multiply|乘)/.test(text)) {
      return {
        tool: {
          name: "calculator",
          input: { operation: "multiply", a: 42, b: 8 },
          result: "336",
        },
        reply:
          "42 × 8 = 336。\n\ncalculator 工具在 MoonBit 进程内完成运算，结果通过 tool-execution-result 事件回灌给模型，再由模型生成最终回答。整个过程是一轮完整的多步工具循环。",
        usage: [12, 48, 2],
      };
    }

    if (/(weather|天气|杭州|温度)/.test(text)) {
      return {
        tool: {
          name: "get_weather",
          input: { city: "Hangzhou" },
          result: "24°C, partly cloudy, humidity 62%",
        },
        reply:
          "杭州今天 24°C，多云转晴，湿度 62%，风力 2 级。\n\n这个结果来自本地 fixture，不依赖外部网络；换成真实 provider 时，同一套工具契约无需修改。",
        usage: [18, 52, 2],
      };
    }

    if (/(moonai|multi-step|多步|工具调用|tool calling)/.test(text)) {
      return {
        tool: {
          name: "search_moonai",
          input: { query: "multi-step tool calling" },
          result: "stream_text loops: model -> tool input -> execute -> tool result -> model",
        },
        reply:
          "MoonAI 的多步循环由 generateText / streamText 驱动：模型先输出工具调用，SDK 解析并执行 MoonBit 工具，再把结果作为新的消息回灌模型，直到触发停止条件（如 stepCount(4)）。\n\n每一步都会产生 step-finish 事件，最终汇总为带 usage 的 finish 事件。",
        usage: [24, 76, 3],
      };
    }

    return {
      tool: null,
      reply:
        "这是浏览器内的静态复刻，只演示事件语义，不会真正调用模型。\n\n试试上面的「计算 42 × 8」或「杭州天气」，可以看到工具输入流、执行结果与步进统计。真实的流式与工具执行在 examples/web_agent 中，由 MoonBit native 后端提供。",
      usage: [9, 36, 1],
    };
  };

  const runDemo = async (prompt) => {
    if (busy) return;
    busy = true;
    sendButton.disabled = true;
    input.disabled = true;
    setStatus("Streaming", "streaming");

    clearEmptyState();
    addUserMessage(prompt);
    input.value = "";

    const plan = planFor(prompt);
    const message = addAssistantMessage();

    await wait(320);

    if (plan.tool) {
      await runTool(message.body, plan.tool);
      addActivityRow("model · step 2");
    }

    await typeText(message, plan.reply);
    message.caret.remove();

    await wait(180);
    setUsage(plan.usage[0], plan.usage[1], plan.usage[2]);
    setStatus("Done", "done");

    busy = false;
    sendButton.disabled = input.value.trim().length === 0;
    input.disabled = false;
    input.focus();
  };

  composer.addEventListener("submit", (event) => {
    event.preventDefault();
    const prompt = input.value.trim();
    if (!prompt) return;
    runDemo(prompt);
  });

  input.addEventListener("input", () => {
    sendButton.disabled = busy || input.value.trim().length === 0;
  });

  if (suggestions) {
    suggestions.addEventListener("click", (event) => {
      const button = event.target.closest("button[data-prompt]");
      if (!button || busy) return;
      runDemo(button.dataset.prompt);
    });
  }

  setUsage(0, 0, 0);
})();
