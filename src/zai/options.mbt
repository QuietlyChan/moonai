///|
/// Z.AI chat model ids from the official OpenAPI specification
/// (https://docs.z.ai/openapi.json, retrieved 2026-08-26 upstream).
pub type ZaiChatModelId = String

///|
/// Provider options accepted under the `zai` namespace:
///
/// - `doSample` (bool): enable or disable sampling; temperature and top_p
///   take no effect when disabled.
/// - `thinking` (object): `{ type: "enabled" | "disabled", clearThinking:
///   bool }`, controlling model thinking and whether reasoning from earlier
///   turns is kept.
/// - `reasoningEffort` (string): `"none" | "minimal" | "low" | "medium" |
///   "high" | "xhigh" | "max"` for GLM-5.2 and later models.
/// - `toolStream` (bool): incremental function-call argument streaming on
///   supported models.
/// - `requestId` (string): caller-provided request identifier, 6-64 chars.
/// - `userId` (string): non-sensitive end-user identifier, 6-128 chars.
