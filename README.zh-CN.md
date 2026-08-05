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

- 提供模型服务商无关的文本、embedding、图片、视频、语音、转录、翻译、realtime、
  Files 与 Skills 模型/服务契约。
- 提供 `generate_text`、`stream_text`、`generate_object`、`embed`、
  `embed_many`、媒体生成、上传、缓冲转录与实时 `stream_transcribe` 标准层 API。
- 通过 JSON 和 SSE 实现可复用的 Open Responses 协议层，并在其上提供独立的官方
  OpenAI Responses 模型与 options 层。
- 通过 JSON 和 SSE 实现 OpenAI-compatible Chat Completions，并支持
  embedding、legacy completion 和图片生成。
- 通过 JSON 实现 Anthropic Messages 非流式调用，并通过 SSE 实现流式调用，包括
  thinking 和 `tool_use` 内容块。
- 支持 OpenAI 缓冲音频转录，以及基于公共 `AudioStream` 契约的 Realtime Whisper
  实时转录。
- 支持文本、URL/base64 图片、音频和文件输入；适配器不支持的媒体类型会明确报错。
- 统一文本、推理、工具调用、结束原因、错误、用量事件，并可选择透传服务商原始事件。
- 支持交错、并行 tool call delta 的增量组装。
- 支持标准采样与推理强度参数、JSON Schema 响应格式、带命名空间的 provider
  options，以及可覆盖 provider 默认值的调用级 HTTP headers。
- 支持原始请求/响应诊断、provider metadata、typed warnings、可配置重试和协作式取消。
- 为每类核心模型提供确定性 mock、golden SSE fixture 和本地 HTTP 集成测试。

## 包结构

| 包 | 用途 |
| --- | --- |
| `QuietlyChan/moonai/ai` | 生成、embedding、媒体、上传和 realtime 等高层工作流 |
| `QuietlyChan/moonai/ai/prompt` | Prompt URL/文件规范化，以及按模型能力下载资源 |
| `QuietlyChan/moonai/ai/model` | Provider-qualified 模型身份、直接/命名引用和 registry 解析 |
| `QuietlyChan/moonai/ai/registry` | Provider-qualified 模型查找，以及 provider 级 Files/Skills registry |
| `QuietlyChan/moonai/provider` | 模型无关的契约、调用参数、响应、事件和诊断类型 |
| `QuietlyChan/moonai/provider_utils` | 可复用的 HTTP、SSE、JSON、multipart、URL、WebSocket、重试和流式工具 |
| `QuietlyChan/moonai/openai` | 带 typed options 和模型能力解析的官方 OpenAI Chat/Responses 模型 |
| `QuietlyChan/moonai/open_responses` | 可复用的 Open Responses 编码、解码与 transport 协议层 |
| `QuietlyChan/moonai/openai_compatible` | 可复用的 Chat Completions、embedding、completion 和图片适配器 |
| `QuietlyChan/moonai/anthropic` | Anthropic Messages、Files 和 Skills API 服务商适配器 |
| `QuietlyChan/moonai/alibaba` | Alibaba DashScope Chat、embedding 和视频适配器 |
| `QuietlyChan/moonai/deepseek` | DeepSeek Chat Completions 适配器 |
| `QuietlyChan/moonai/minimax` | MiniMax Chat 和视频适配器 |
| `QuietlyChan/moonai/testing` | 面向模型无关契约的确定性 mock model |
| `QuietlyChan/moonai/cmd/main` | 可选的冒烟测试程序，使用库时不需要该包 |

这些基础包分别对应 AI SDK 的 `packages/ai`、`packages/provider`、
`packages/provider-utils`，以及 `packages/ai` 中的 registry 部分。Provider 实现依赖
`provider` 与 `provider_utils`；
应用通常组合使用 `ai`、`provider` 和一个具体 provider 包。MoonBit 目前不能重导出
enum 构造器，因此 `V4TextDelta`、`V4FinishStop`、`High` 等值应直接通过 `@provider` 使用。

`src/ai/prompt` 对应 AI SDK 的 prompt 转换边界，负责 URL/file 资源规范化，并独立于
高层生成流程。项目不会提供根模块兼容包；在 `1.0.0` 之前 API 可以直接演进，使用者应
直接依赖上面的具名包。旧的 `src/internal` 实现包也已经删除；只有拥有稳定依赖边界的
领域才会成为独立 MoonBit 包，较小的工具仍按职责放在所属包内。`ai/model` 与
`ai/registry` 也是独立包，因为模型身份和 provider 注册表有稳定的依赖边界。

源码目录与抽象边界不是一回事。重要领域都有对应的 MoonBit 抽象：面向调用方的
语言、embedding、图片主契约分别是 `provider::LanguageModelV4`、
`provider::EmbeddingModelV4`、`provider::ImageModelV4`；prompt 规范化独立放在
`ai/prompt`；可替换的 provider HTTP 由 `provider_utils` 中的 `HttpTransport` trait 承载。
所有 provider 工厂都接受可选的 `http_transport`，并将其传播到普通响应、流式响应、multipart、
二进制、下载和轮询请求。`ChatModel`、`EmbeddingWireModel`、`ImageWireModel` 只保留在
明确的协议 wire/第三方 adapter 边界，不是高层模型 API。

面向调用方的 `ModelMessage` 与 `ModelContentPart` 定义在 `provider_utils`，对应 AI SDK
的公共 prompt 类型；`ai/prompt` 会把它们转换成独立的
`provider::LanguageModelMessage` 契约。因此 provider 编码器不会意外接收未经校验的
高层消息。

AI SDK 的 `packages/ai/src/model` 并不定义 provider 模型契约，它负责解析字符串模型
标识，并把旧的 V2/V3 契约适配成 V4。Moonai 将调用契约保留在 `provider`，而由
`ai/model` 负责 provider-qualified 的 `ModelId`、直接/命名模型引用、typed registry
和版本适配。所有内置语言 provider 都由各自包暴露 provider-owned
`LanguageModelV4` 实现；通用的 `@model.as_language_model_v4` 仅用于显式的第三方模型与
wire 层集成边界，不是根模块旧 API 兼容层。

两个 registry 的职责不同：`ai/model::ModelRegistry` 按规范身份保存已经构造好的模型实例；
`ai/registry::ProviderRegistry` 保存 provider 工厂，按 `provider:model` 延迟选择模型，并提供
provider 级 Files 和 Skills 能力。后者对应 AI SDK 的 `createProviderRegistry` 抽象层。

`ai/registry::custom_provider` 对应 AI SDK 的 `customProvider`：调用方可以按模型契约
注入自己的 `LanguageModelV4`、embedding、媒体或语音模型；没有命中的模型和 Files/Skills
能力会按需委托给 `fallback_provider`。这使 `provider` trait、`ai/prompt` 和
`provider_utils::HttpTransport` 都能在应用层组合，而不需要根模块兼容门面。

`ai/model` 还提供 language、embedding、image 三类 V4 middleware 及其 wrapper/chain；
`ProviderRegistry` 的 language/image middleware 参数会在 V4 模型解析后应用参数变换、
identity override 以及操作包装。它们是 MoonBit 对 AI SDK V4 middleware 契约的公共抽象，
不是旧 API 兼容代码。`ChatModel` 到 V4 的 adapter 只用于显式的第三方模型与 wire 层集成边界。

## 安装

该包尚未发布到 Mooncakes。首次发布后可通过以下命令安装：

```shell
moon add QuietlyChan/moonai
```

同时使用核心 API 和 OpenAI 适配器的包需要声明：

```moonbit
import {
  "QuietlyChan/moonai/ai",
  "QuietlyChan/moonai/provider",
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
let result = @ai.generate_text(
  model,
  prompt="用三句话解释 MoonBit。",
  instructions=@ai.Instructions::text("回答要简洁。"),
)
```

MoonBit 的规范入口是 `generate_text`。当前也提供 AI SDK 风格的 `generateText` 拼写，
这是命名对齐便利，不代表会长期保留旧版 Moonai API。

`generate_text`、`stream_text` 和 `generate_object` 共用 `ai/prompt` 的标准化边界。
`instructions` 只接受 system message，并会放在普通消息之前；普通 `messages` 默认不允许
包含 system role。仅在迁移已经包含 system message 的消息历史时，才显式设置
`allow_system_in_messages=true`。

## 流式文本生成

```moonbit
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

MoonBit 代码通常应优先使用 `stream_text`。`streamText` 别名主要方便熟悉
TypeScript AI SDK API 的开发者理解和迁移。

设置 `include_raw_chunks=true` 后，每个解析完成的服务商数据块会先以
`StreamEvent::Raw` 发出，然后再发出标准化事件。文本、completion、embedding 和
图片调用也支持调用级 `headers`，同名 header 会覆盖 provider 的默认配置。

## 诊断、重试与取消

每种标准化响应都提供 `request`、`response`、`provider_metadata` 和 typed
`warnings`。非流式响应会保留原始响应 body；流式响应不会缓存完整 body，如需检查
原始 SSE 数据，应设置 `include_raw_chunks=true`。

标准化 `Usage` 会分别记录 reasoning、cache read 和 cache write 用量。provider 通过
`cache_write_input_tokens` 返回缓存写入 token；批量调用聚合 usage 时也会保留该值。

高层 prompt 形状或消息角色不合法时会抛出 `InvalidPromptError`，参数取值不合法时会
抛出 `InvalidArgumentError`。provider 返回成功 HTTP 状态但响应结构不合法时使用
`InvalidResponseDataError`；视频等异步任务超过轮询期限时使用
`ProviderTimeoutError`，与 HTTP 层的 `APICallError` 分开处理。

```moonbit
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
  prompt="解释 MoonBit。",
  retry_policy~,
  cancellation_token=cancellation,
)
```

默认策略会对网络错误、超时、HTTP 408/409/425/429 和 5xx 响应进行最多两次指数
退避重试。SSE 只会在 `StreamStart` 发出前重试，避免文本或工具事件重复。可通过
`RetryPolicy::none()` 禁用重试，通过 `cancellation.cancel()` 取消协作式操作。

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

官方 provider 分别实现 `OpenAIResponsesModel` 和 `OpenAIChatModel`。两者拥有各自的
typed provider options 和模型能力解析，用于推理参数、消息角色与不兼容参数过滤；
只在协议解码和 transport 工具层复用基础实现。

官方 provider 可以统一配置 organization 和 project，之后选择的所有模型都会继承：

```moonbit
///|
let provider = @openai.create_openai(
  api_key~,
  organization="org-example",
  project="proj-example",
)
```

显式传入的自定义 headers 优先于 API key、organization 和 project 生成的 headers；
header 名称按大小写不敏感规则覆盖。

官方 Chat metadata 包含 accepted/rejected prediction token 数量和 logprobs；官方
Responses metadata 包含 response id、service tier、reasoning context 和 logprobs。
JSON 与 SSE 调用都会在官方 provider 的 `provider_metadata` 命名空间中累计这些字段。

## Anthropic Messages

```moonbit
///|
let model = @anthropic.anthropic(
  "claude-sonnet-4-20250514",
  api_key=@env.get_env_var("ANTHROPIC_API_KEY").unwrap(),
)

///|
let response = @ai.stream_text(
  model,
  prompt="用三句话解释 MoonBit。",
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

Anthropic 通过共享的 prepared-request 层同时支持原生 `generate_text` 与
`stream_text`。标准化 `reasoning_effort` 会根据模型能力映射：较新的 Claude 模型
使用 adaptive thinking 与 effort，旧模型使用 extended-thinking token budget。
provider 专有覆盖仍放在 `provider_options.anthropic` 下。

Messages 支持文本、URL/base64 图片和 PDF 等 document 文件 part。由于 Messages API
不接受音频，audio part 会在发出请求前明确报错。

Provider 还提供 `files()` 与 `skills()`。Files API 上传后返回 provider-neutral reference；
Skills API 支持多个 `files[]`、可选 display title、必需的 beta header，并会继续读取最新
版本的 name 与 description metadata。两者都复用 Messages 的认证、自定义 headers 和
可注入 `HttpTransport`。

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

provider 级 `query_params` 会应用到 chat、completion、embedding 和 image 端点。
只有兼容端点确实接受 OpenAI `json_schema` 响应格式时，才应开启结构化输出：

```moonbit
///|
let provider = @openai_compatible.create_openai_compatible(
  provider_name="example-gateway",
  base_url="https://example.com/v1",
  api_key~,
  query_params={ "api-version": "2026-08" },
  supports_structured_outputs=true,
)
```

compatible provider factory 可传入 `transform_request_body`，在 typed request
准备完成后、HTTP transport 发送前执行网关专有的 body 调整。

compatible provider 还可以替换 `error_structure`、`metadata_extractor` 和
`convert_usage`。JSON/SSE transport 以及 chat、completion、embedding、image
模型共享 error structure；metadata 和 usage hook 用于非流式与流式 chat 响应。
每个流式请求都会创建独立的 metadata extractor，因此并发调用不会共享状态。

未开启该选项时，JSON Schema 请求会回退为 `json_object`，并返回 typed warning，
不会错误地声称服务端执行了 schema 约束。

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

该协议包先把命名空间 options 解析为 typed 值并生成带 warnings 的 prepared
request，再编码 wire body 并交给 transport。第三方 provider 可以复用这条管线，
而不会继承官方 OpenAI 的模型能力规则。

编码器支持 URL 文件输入，并通过 `Message::tool_parts` 支持多模态 tool result。
解码器会为完整 JSON 响应与交错 SSE 事件统一组装 text、refusal、reasoning、tool
argument delta、终态、usage 和 provider metadata。

## Provider options 与推理强度

跨 provider 的推理控制应优先使用标准化 `reasoning_effort`。适配器会在协议支持时
映射到对应字段；发生值降级或协议无法表达时，会返回 typed warning。

provider 专有请求字段采用 AI SDK 的命名空间约定。命名空间是 `provider_name` 的
camelCase 形式，例如 `example-gateway` 对应 `exampleGateway`：

```moonbit
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
  prompt="解释其中的取舍。",
  provider_options={
    "exampleGateway": {
      "reasoningEffort": "high",
      "user": "user-1",
    },
  },
)
```

provider options 必须放在对应的 provider 命名空间下。`model`、`messages`、
`stream` 等由标准请求负责的字段会被忽略，并产生 compatibility warning。

## 结构化输出与多模态输入

```moonbit
///|
let object = @ai.generate_object(
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
let response = @ai.generate_text(
  model,
  messages=[
    @ai.ModelMessage::user_parts([
      @ai.ModelContentPart::text("描述这张图片。"),
      @ai.ModelContentPart::image_url("https://example.com/moon.png"),
    ]),
  ],
)
```

OpenAI-compatible Chat Completions 支持文本、图片、base64 音频和 base64 PDF。
图片 URL 会直接透传，`text/*` 文件 URL 会转换为文本，PDF/音频文件 URL 会在
transport 前被拒绝，与 AI SDK 一致。官方 OpenAI Chat 同样透传图片 URL，并拒绝
其他文件 URL。Open Responses 支持图片 URL、文件 URL、base64 文件和多模态 tool
result，并明确拒绝音频输入。Anthropic Messages 支持文本、图片和 document part，
并同样明确拒绝音频。`generate_object` 会请求 JSON Schema 输出、解析最终 JSON，
并通过公共 `provider_utils` 校验返回值；解析失败或 schema 不匹配时会抛出带有
结构化原因的 `NoObjectGeneratedError`。

## Embedding、Completion 和图片

官方 OpenAI provider 与 OpenAI-compatible provider 使用相同的模型选择器：

```moonbit
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
  prompt="MoonBit 是",
)

///|
let images = @ai.generate_image(
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

## 设计方向

核心库将保持模型服务商无关。服务商特有的协议格式、认证方式和配置应放在对应的
适配包中。后续计划包括 source 和生成文件等更丰富的输出内容、图片编辑、中间件、
遥测接口和更高层的多步工具执行能力。

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
