# Framework 同步 SOP

> PM-AI-Workflow 主仓改动后，把 framework 资产推到已 init 的目标项目（如 ExampleConsumerApp）。

## 同步范围（4 块缺一不可）

| 主仓位置 | 目标项目位置 | 内容 |
|---|---|---|
| `skills/` | `.claude/skills/` | 所有 skill 定义（除 `init-project/`，仅主仓保留） |
| `scripts/` | `.claude/scripts/` | 所有运行时脚本（除 `init-project.sh`） |
| `templates/` | `templates/` | 模板源文件 `.tmpl`、工程结构约束、git-hooks |
| `agents/` | `.claude/agents/` | 自定义 subagent 定义 |

**判断"对齐"的唯一标准**：上述 4 块的 `diff -rq` 全部零差异。只看 1-2 块就声称对齐 = 错。

## 工具

```bash
# 默认 dry-run，只 audit + 列差异
bash scripts/sync-to-project.sh <project-dir>

# 真执行（保留目标侧多余文件）
bash scripts/sync-to-project.sh <project-dir> --apply

# 真执行 + 删除目标侧 framework 范围内多余文件
bash scripts/sync-to-project.sh <project-dir> --apply --confirm-deletes
```

工具行为：
- 4 块 `diff -rq` audit；0 差异直接 exit 0
- rsync `--checksum` 比较内容（忽略 mtime-only 差异，避免误报）
- 默认不删 dst 多余文件（避免误删本地自定义）；`--confirm-deletes` 才允许删
- apply 后再跑一次 `diff -rq` 复查，零差异才报"完成"

## 标准流程

### 主仓改完之后
```bash
# 1. PM-AI-Workflow 主仓 commit
cd ${REPO_ROOT}
git add ... && git commit -m "..."

# 2. dry-run 看落差
bash scripts/sync-to-project.sh /path/to/project

# 3. PM 确认 dry-run 输出 OK 后，--apply
bash scripts/sync-to-project.sh /path/to/project --apply
# 若有需要删的废弃文件:
bash scripts/sync-to-project.sh /path/to/project --apply --confirm-deletes

# 4. 在目标项目 main 分支 commit
cd /path/to/project
git status  # 检查 .claude/ + templates/ 改动
git add -A .claude/ templates/
git commit -m "chore: 同步框架 — <一句话描述本次同步内容>"
```

### 功能分支 merge main
main 同步完成后，各功能分支（req-* / task-*）通过 `git merge main` 拿到 framework 更新：

```bash
cd /path/to/project-worktree-of-feature-branch
git merge main
# 若 framework 文件冲突（PM-VIEW-RULES.md / SKILL.md 等），用 main 版本覆盖:
git checkout --theirs .claude/ templates/
git add .claude/ templates/
git commit
```

framework 永远以 main 为准，功能分支不应在 framework 文件上做本地修改。

## 与 `init-project.sh` 的边界

- **init**：从零创建新项目；替换占位符（`{{PROJECT_NAME}}` 等）；做 `git init` / 创建目录骨架。
- **sync**（本工具）：已 init 项目的 framework 升级；**不替换占位符**（不动业务实例如 `CLAUDE.md` / `docs/CONTEXT.md`）；不做 git 操作。

不要在已 init 项目上跑 `init-project.sh`——会破坏业务文件的占位符替换逻辑。

## 这次同步踩过的 5 个坑（避免重蹈）

1. **声称对齐 vs 实际对齐**——只 diff `skills + scripts` 就说"对齐"，漏掉 `templates`（5 个 `.tmpl` 落后）。修法：本工具强制做 4 块 audit。
2. **以为只同步本次改动**——一次同步只拷贝当前 commit 的文件，但累积漏同步了 7 次历史 commit 的 28 个 framework 文件。修法：本工具 audit 看完整落差，不只看当前改动。
3. **`init-project.sh` 不能直接套**——它替换占位符，会破坏已 init 项目的 `CLAUDE.md`。修法：本工具与 init 严格分离，不动业务实例。
4. **`init-project.sh` 自身有 bug**——`cp "$SKILL_DIR"*` 不递归子目录，`references/` 子文件被漏。修法：本工具用 `rsync -a` 递归。
5. **`rsync --delete` 无保护**——可能误删 dst 合法本地文件。修法：默认不 `--delete`，需显式传 `--confirm-deletes` 才删。
