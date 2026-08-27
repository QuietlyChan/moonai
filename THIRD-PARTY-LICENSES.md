# 第三方依赖与许可证

本文件记录 `moonai` 直接使用的第三方项目、参考项目和示例依赖。项目自身代码采用
Apache License 2.0，完整文本见 [LICENSE](LICENSE)。仓库没有复制 Vercel AI SDK 或其他
第三方项目的源代码、图片和字体；`README.md` 中的 API/协议对应关系属于设计参考。

## MoonBit 运行时依赖

| 项目 | 版本 | 用途 | 许可证 | 链接 |
| --- | --- | --- | --- | --- |
| `moonbitlang/async` | `0.20.2` | native 异步运行时 | Apache-2.0 | https://github.com/moonbitlang/async |
| `cc06b/mooncry` | `0.13.1` | 加密、哈希和编码工具 | Apache-2.0 | https://github.com/cc06b/mooncry |

版本约束记录在 [moon.mod](moon.mod)，依赖源码和许可证元数据由 Mooncakes lockfile
解析。发布包只声明并链接这些依赖，不重新分发其独立项目的源文件。

## 参考项目

| 项目 | 用途 | 许可证 | 链接 |
| --- | --- | --- | --- |
| Vercel AI SDK | 公开 API、协议和包边界的设计参考 | Apache-2.0 | https://github.com/vercel/ai |

本项目是独立实现，不是 Vercel 官方项目，也不使用 Vercel 商标作为项目名称。

## React `useChat` 示例依赖

`examples/react_use_chat` 是可选的前端示例，不属于 MoonBit 库运行时依赖。其直接依赖及
许可证为：`ai`、`@ai-sdk/react` 和 `typescript`（Apache-2.0），`react`、`react-dom`、
`zod`、`vite`、`@vitejs/plugin-react`、`@types/react` 和 `@types/react-dom`（MIT），以及
`lucide-react`（ISC）。精确版本、
解析地址和传递依赖的许可证字段记录在该目录的
[package-lock.json](examples/react_use_chat/package-lock.json)；安装或发布示例时应保留
该文件及各 npm 包随附的许可证声明。

示例前端没有下载或嵌入受限素材；页面样式、图标使用和 MoonBit 生成的静态资源均为本
项目新增内容。发现新增第三方代码或素材时，应在本文件补充来源、版本、许可证和归属。
