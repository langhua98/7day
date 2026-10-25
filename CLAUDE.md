# 给 Claude 的仓库规则

## iOS 编译（必须遵守）

- **编译前必须由 William 提出。** William 没有在对话里明确要求时，不要触发、重跑或重新排队 iOS 安装包编译（`.github/workflows/ios.yml`）。
- 编译只能手动触发：GitHub → Actions → iOS 安装包 → Run workflow（`workflow_dispatch`）。推送 main、开 PR、合并 PR 都不会自动编译，不要再把 `push` / `pull_request` 触发加回去。
- 不要为了“让 CI 变绿”去手动触发编译。改完代码先在本地用 Godot 4.7.2 无头模式跑 `tests/` 里的测试。
- 编译失败时先看日志、找原因、修代码，再问 William 要不要重新编译。

其他开发规则见 `docs/任务书.md` 第五节“通用规则”。
