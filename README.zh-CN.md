# moonai

[English](README.md) | 简体中文

[![CI](https://github.com/QuietlyChan/moonai/actions/workflows/ci.yml/badge.svg)](https://github.com/QuietlyChan/moonai/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![MoonBit](https://img.shields.io/badge/MoonBit-native-F5A623.svg)](https://www.moonbitlang.com/)

面向 MoonBit 的统一、模型服务商无关 AI SDK。

`moonai` 希望把 [Vercel AI SDK 7](https://ai-sdk.dev/) 的标准层设计带到
MoonBit，包括统一模型接口、标准化流事件、服务商适配器、工具调用，以及可测试的
核心层，方便应用在此基础上继续构建。

这是一个由社区独立开发的项目，与 Vercel 没有隶属关系。

> 当前状态：早期 alpha。`1.0.0` 之前 API 可能发生变化。当前版本仅支持 native
> 目标，重点实现 OpenAI-compatible 流式调用。

## 当前阶段

- 提供模型服务商无关的 `ChatModel` 接口。
- 提供 `stream_text` API，并保留 `streamText` 兼容别名。
- 通过 HTTP 和 SSE 实现 OpenAI-compatible Chat Completions 流式调用。
- 统一文本、推理、工具调用、结束原因、错误和用量事件。
- 支持交错、并行 tool call delta 的增量组装。
- 提供 mock model、golden SSE fixture 和本地 HTTP 集成测试。

## 包结构

| 包 | 用途 |
| --- | --- |
| `QuietlyChan/moonai` | 模型、消息、工具、流事件和响应等核心类型 |
| `QuietlyChan/moonai/openai` | OpenAI 及 OpenAI-compatible 服务商适配器 |
| `QuietlyChan/moonai/testing` | 用于应用测试的确定性 mock model |
| `QuietlyChan/moonai/cmd/main` | 可选的冒烟测试程序，使用库时不需要该包 |

## 安装

该包尚未发布到 Mooncakes。首次发布后可通过以下命令安装：

```shell
moon add QuietlyChan/moonai
```

同时使用核心 API 和 OpenAI 适配器的包需要声明：

```moonbit
import {
  "QuietlyChan/moonai",
  "QuietlyChan/moonai/openai",
}
```

## 流式文本生成

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

MoonBit 代码通常应优先使用 `stream_text`。`streamText` 别名主要方便熟悉
TypeScript AI SDK API 的开发者理解和迁移。

## OpenAI-compatible 服务商

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

初始 API 沿用了部分开发者熟悉的 AI SDK 概念，同时保留 MoonBit 自身的命名习惯：

| Vercel AI SDK | moonai |
| --- | --- |
| `streamText({ model, prompt })` | `@moonai.stream_text(model, prompt=...)` |
| `openai("gpt-4.1")` | `@openai.openai("gpt-4.1", api_key=...)` |
| `createOpenAI({ baseURL })` | `@openai.create_openai(base_url=..., api_key=...)` |

## 设计方向

核心库将保持模型服务商无关。服务商特有的协议格式、认证方式和配置应放在对应的
适配包中。后续计划包括非流式生成、结构化输出、更多服务商适配器、中间件、重试、
遥测接口和更高层的工具执行能力。

Agent 工作流和沙箱化工具运行时属于后续层次。它们会建立在该 SDK 之上，不会与
具体服务商协议耦合。

## 开发

```shell
moon info
moon fmt --check
moon check
moon test
```

可选的冒烟测试程序可以通过以下命令运行：

```shell
OPENAI_API_KEY=... moon run src/cmd/main
```

MoonBit 工具链使用的文档位于 [`README.mbt.md`](README.mbt.md)。

## 许可证

项目采用 [Apache License 2.0](LICENSE)。
