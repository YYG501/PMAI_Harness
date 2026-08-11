# TODOS

> 只放开放项。已完成或已废弃的设计、迁移和兼容计划不在这里保留存根。

## 后续验证

- 在一个全新消费仓真实跑 `/pmai-init-project` → `/pmai-proposal` → `/pmai-design`（内部调用 `/pmai-spec-writing` 并生成 `project.yml`）→ `/pmai-build` 自动 finalize，验证产品基线、规格编译、定义生成、工作环境、adaptive acceptance、合入 main 和文档编译闭环。
- 分别 dogfood 一次 Web product 和非 Web product：前者验证主动浏览器硬门，后者验证无 prototype/dev port/browser 仍可合法完成。
