name = "QuietlyChan/moonai"

source = "src"

version = "0.1.0"

import {
  "moonbitlang/async@0.20.2",
  "cc06b/mooncry@0.13.1",
}

readme = "README.mbt.md"

repository = "https://github.com/QuietlyChan/moonai"

license = "Apache-2.0"

keywords = [
  "ai",
  "ai-sdk",
  "llm",
  "openai",
  "openai-compatible",
  "open-responses",
  "anthropic",
  "streaming",
  "tool-calling",
]

description = "Unified, provider-neutral AI SDK for MoonBit inspired by Vercel AI SDK 7"

preferred_target = "native"

supported_targets = "+native"

warnings = "+missing_doc+unused_default_value"
