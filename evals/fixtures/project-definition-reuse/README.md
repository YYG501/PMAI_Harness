# Session Eval Fixture: project-definition-reuse

Harness 建立与当前规格、source hash、checkpoint、revision 和批准路径完全一致的 ready。
重试必须幂等复用 `.pm-workflow/project.yml`，不能重写项目建造定义或递增 revision。
