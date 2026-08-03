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

> 当前状态：早期 alpha。`1.0.0` 之前 API 可能发生变化。当前版本支持 native
> 目标，支持非流式与流式文本生成、embedding、legacy completion、图片生成和
> Anthropic Messages。

## 当前阶段

- 提供模型服务商无关的 `ChatModel`、`EmbeddingModel`、`CompletionModel` 和
  `ImageModel` 接口。
- 提供 `generate_text`、`stream_text`、`generate_object`、`embed`、
  `embed_many`、`complete`、`stream_completion` 和 `generate_image` 标准层 API。
- 通过 JSON 和 SSE 实现 Open Responses 调用，官方 OpenAI 默认使用该协议。
- 通过 JSON 和 SSE 实现 OpenAI-compatible Chat Completions，并支持
  embedding、legacy completion 和图片生成。
- 通过 HTTP 和 SSE 实现 Anthropic Messages 流式调用，包括 thinking 和
  `tool_use` 内容块。
- 支持文本、URL/base64 图片、音频和文件输入；适配器不支持的媒体类型会明确报错。
- 统一文本、推理、工具调用、结束原因、错误、用量事件，并可选择透传服务商原始事件。
- 支持交错、并行 tool call delta 的增量组装。
- 支持标准采样参数、JSON Schema 响应格式，以及可覆盖 provider 默认值的调用级
  HTTP headers。
- 为每类核心模型提供确定性 mock、golden SSE fixture 和本地 HTTP 集成测试。

## 包结构

| 包 | 用途 |
| --- | --- |
| `QuietlyChan/moonai` | 语言、embedding、completion、图片、工具、流事件和响应等核心 API |
| `QuietlyChan/moonai/openai` | 组合共享协议实现的官方 OpenAI 适配器 |
| `QuietlyChan/moonai/open_responses` | 可复用的 Open Responses 协议适配器 |
| `QuietlyChan/moonai/openai_compatible` | 可复用的 Chat Completions、embedding、completion 和图片适配器 |
| `QuietlyChan/moonai/anthropic` | Anthropic Messages API 服务商适配器 |
| `QuietlyChan/moonai/testing` | 用于应用测试的 chat、embedding、completion、图片 mock model |
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

如果要基于这两种协议开发第三方服务商适配器，可直接依赖
`QuietlyChan/moonai/openai_compatible` 或
`QuietlyChan/moonai/open_responses`。

## 非流式文本生成

```moonbit
///|
let model = @openai.openai(
  "gpt-4.1-mini",
  api_key=@env.get_env_var("OPENAI_API_KEY").unwrap(),
)

///|
let result = @moonai.generate_text(
  model,
  prompt="用三句话解释 MoonBit。",
)
```

`generateText` 是为 AI SDK 用户保留的兼容别名。

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

设置 `include_raw_chunks=true` 后，每个解析完成的服务商数据块会先以
`StreamEvent::Raw` 发出，然后再发出标准化事件。文本、completion、embedding 和
图片调用也支持调用级 `headers`，同名 header 会覆盖 provider 的默认配置。

`@openai.openai(...)` 和 `OpenAIProvider::language_model(...)` 默认使用
Responses API，与 AI SDK 7 保持一致。如需 Chat Completions，可使用
`@openai.openai_chat(...)` 或 `OpenAIProvider::chat(...)`：

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
  prompt="用三句话解释 MoonBit。",
  on_event=event => {
    match event {
      @moonai.TextDelta(delta~, ..) => @stdio.stdout.write(delta)
      @moonai.ReasoningDelta(delta~, ..) => ()
      _ => ()
    }
  },
)
```

## OpenAI-compatible 服务商

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

旧的 `@openai.openai_compatible(...)` 快捷入口仍然保留，但新的服务商集成应
直接依赖独立协议包。

## Open Responses 服务商

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

## 结构化输出与多模态输入

```moonbit
///|
let object = @moonai.generate_object(
  model,
  {
    "type": "object",
    "properties": { "answer": { "type": "string" } },
    "required": ["answer"],
  },
  prompt="请使用 JSON 回答。",
  name="answer",
)

///|
let response = @moonai.generate_text(
  model,
  messages=[
    @moonai.Message::user_parts([
      @moonai.ContentPart::text("描述这张图片。"),
      @moonai.ContentPart::image_url("https://example.com/moon.png"),
    ]),
  ],
)
```

OpenAI-compatible Chat Completions 支持文本、图片、音频和文件 part。Open
Responses 支持文本、图片和文件，对音频输入会明确报错。`generate_object` 会请求
JSON Schema 输出并解析最终 JSON；目前还没有在客户端校验返回值是否符合 schema。

## Embedding、Completion 和图片

官方 OpenAI provider 与 OpenAI-compatible provider 使用相同的模型选择器：

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
  "MoonBit 是",
)

///|
let images = @moonai.generate_image(
  provider.image("gpt-image-1"),
  "一枚精确的 MoonBit 语言标志",
  n=2,
  size="1024x1024",
)
```

`embed_many` 和 `generate_image` 都会根据模型的单次请求上限自动拆分，保持结果
顺序、校验返回数量并累加 usage。图片数据明确标记为 `ImageData::Base64` 或
`ImageData::Url`。

provider 的 snake_case 选择器同时提供 AI SDK 风格的 camelCase 别名，包括
`languageModel`、`embeddingModel`、`completionModel` 和 `imageModel`。

初始 API 沿用了部分开发者熟悉的 AI SDK 概念，同时保留 MoonBit 自身的命名习惯：

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

## 设计方向

核心库将保持模型服务商无关。服务商特有的协议格式、认证方式和配置应放在对应的
适配包中。后续计划包括 provider metadata 与原始请求/响应信息、source 和生成文件等
更丰富的输出内容、图片编辑、中间件、重试、取消、遥测接口和更高层的多步工具执行
能力。

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
