---
name: publish-to-lark
description: 把本地 markdown 文档发布到飞书云文档，发布后自动合并表格中相邻相同内容的 cell。首次发布回填飞书 URL 到 markdown frontmatter，下次按 URL 覆盖原文档。通用发布编排层，被 prd-writing 等 skill 在 stage 末尾调用；PM 也可手动 `/publish-to-lark <markdown 路径> [--type prd|task-spec|analysis|other]`。
---

# /publish-to-lark

## When To Use

- 由 prd-writing 在 stage 6 结束模板调用（D 选项），用于发布 req 级 PRD
- 未来可被 task-spec / analysis / project-prd-update 等其它 skill 复用
- PM 手动调用：`/publish-to-lark <markdown 路径> [--type <type>] [--target-token <token>] [--title <title>]`

## Required Inputs

1. `markdown_path`：要发布的 markdown 文件绝对路径
2. `--type`（可选）：文档类型，决定默认目标位置和命名规则（`prd` / `task-spec` / `analysis` / `other`）
3. `--target-token`（可选）：覆盖默认目标位置（wiki node token 或 folder token）
4. `--target-kind`（可选）：`wiki` 或 `folder`，与 `--target-token` 配套
5. `--title`（可选）：覆盖默认标题
6. `--no-merge-cells`（可选）：跳过表格合并（默认开启合并）

## Configuration

项目级配置存放在 `.claude/lark-publish.json`，结构：

```json
{
  "default_targets": {
    "prd": {
      "kind": "wiki",
      "token": "wikxxx...",
      "title_template": "{req_id} - {req_title} PRD"
    },
    "task-spec": {
      "kind": "folder",
      "token": "fldxxx...",
      "title_template": "{task_id} - {task_title}"
    },
    "analysis": {
      "kind": "wiki",
      "token": "wikxxx...",
      "title_template": "{req_id} 需求分析"
    }
  }
}
```

未配置类型时，PM 必须同时传 `--target-token` + `--target-kind` + `--title`，否则 skill 报错退出。模板见 `$REPO_ROOT/templates/lark-publish.json.tmpl`。

`title_template` 占位符从 markdown frontmatter 或文件名读取（`{req_id}` / `{req_title}` / `{task_id}` / `{task_title}` / `{filename}`）。

## Preflight Check（脚本入口自动执行）

调用 `publish-to-lark.py` 时，脚本头部统一做以下 5 项检查，任一失败即明确报错并退出，不进入实际发布：

| 检查项 | 失败时提示 |
|---|---|
| `lark-cli` 在 PATH | `lark-cli 未安装。安装方式见 https://github.com/larksuite/lark-cli` |
| `lark-cli --version` ≥ `1.0.14` | `lark-cli 版本 <实际值> 低于最低要求 1.0.14；请升级` |
| `lark-cli auth status` 已登录 | `飞书 CLI 未登录。运行 lark-cli auth login（详见 lark-shared skill）` |
| `lark-cli auth check --scopes` 关键 scope 已授权 | `缺少 scope: <list>；请在飞书开放平台为 app 申请 scope 后重新 lark-cli auth login` |
| `.claude/lark-publish.json` 存在 或 命令行参数齐全 | `配置缺失。复制 $REPO_ROOT/templates/lark-publish.json.tmpl 到 .claude/lark-publish.json 并填 token；或手动传 --target-token + --target-kind + --title` |

**版本基线说明：** 1.0.14 是当前已验证的工作版本。lark-cli 后续如发版引入 breaking change，更新本文件并 bump 此版本号。

**关键 scope：** 发布到 wiki 时 `docx:document` + `wiki:wiki:readonly`；发布到 folder 时 `docx:document` + `drive:drive`；合并 cell 还需 `docx:document`。脚本按目标位置类型动态决定要检查的 scope 列表。

## Workflow

### 步骤 1：解析输入

读取 markdown 文件，提取 YAML frontmatter（如有）。

检测 frontmatter 中是否已有 `lark_doc_id`：
- **有** → 走"覆盖现有文档"分支
- **无** → 走"首次发布"分支

### 步骤 2：决定目标位置 + 标题

按以下优先级：

1. 命令行参数 `--target-token` + `--target-kind` + `--title`（最高）
2. `.claude/lark-publish.json` 中 `--type` 对应的配置
3. 都没有 → 报错退出，提示 PM 配置或手动传参

### 步骤 3：发布 markdown

调用 `python3 .claude/scripts/publish-to-lark.py` 执行编排：

**首次发布：**

```bash
lark-cli docs +create \
  --title "<title>" \
  --wiki-node "<token>" \    # 或 --folder-token "<token>"
  --markdown "@<markdown_path>"
```

拿到返回的 `document_id`。

**覆盖发布：**

```bash
lark-cli docs +update \
  --doc "<existing_doc_id>" \
  --markdown "@<markdown_path>" \
  --mode overwrite
```

### 步骤 4：自动合并表格相同内容 cell（默认开启）

发布完成后，扫描文档中所有 table 块：

1. `GET /open-apis/docx/v1/documents/:doc_id/blocks` 拉所有 block
2. 找出所有 `table` block
3. 对每个 table 的每一列：扫描连续多行内容**完全相同**的范围（空字符串不参与）
4. 对每个范围调 `PATCH /open-apis/docx/v1/documents/:doc_id/blocks/:block_id` with `merge_table_cells` 子请求
5. 跳过已存在 `merge_info` 的 cell（避免重复合并）
6. 失败 fail-soft：单次合并失败不阻塞其它合并，最后输出失败计数

### 步骤 5：回填飞书 URL 到 markdown

**首次发布**才执行。在 markdown frontmatter（文件最顶部）写入：

```yaml
---
lark_doc_id: doxcnxxxxxx
lark_doc_url: https://xxx.feishu.cn/docx/doxcnxxxxxx
lark_published_at: 2026-04-27T15:30:00+08:00
---
```

如果原文件已有 frontmatter，合并这三个 key（不动其它 key）；如果没有，创建一个新的。

### 步骤 6：完成

输出：

```text
飞书文档已发布
URL: https://xxx.feishu.cn/docx/doxcnxxxxxx
合并 cell: 成功 N 处 / 失败 M 处
本地 frontmatter: 已回填
```

## Rules

- **单向同步**：本地 markdown 是 source of truth；飞书侧的修改下次发布会被覆盖
- **合并是 fail-soft**：合并失败不阻塞主发布，只输出警告
- **merge cell 判定**：相邻多行同列内容必须**完全相同**才合并；空字符串不参与
- **frontmatter 回填**仅首次发布执行；覆盖发布不动 frontmatter
- **不修改正文**：除 frontmatter 外，本 skill 不改 markdown 任何内容
- **不做 wiki/folder 切换**：首次发布的目标位置一旦定下，覆盖发布只能在同位置；要换位置必须删 frontmatter 中的 `lark_doc_id` 后重新首次发布

## Failure Handling

| 错误类型 | 处理 |
|---|---|
| 配置缺失 | 提示 PM 编辑 `.claude/lark-publish.json` 或手动传 `--target-token` + `--target-kind` + `--title` |
| lark-cli 认证失败 | 提示 PM 跑 `lark-cli auth login`（参考 lark-shared skill）|
| 创建文档失败 | 报错并退出，不进入合并步骤 |
| 覆盖文档失败 | 报错并退出，frontmatter 不动 |
| 拉 block 列表失败 | 警告并跳过合并；主发布仍算成功 |
| 单次合并 cell 失败 | 警告，继续其它合并 |
| frontmatter 写入失败 | 报错，但飞书侧文档已发布成功，提示 PM 手动回填 URL |

## 集成示例

prd-writing 在 stage 6 结束模板加：

```markdown
D) 发布到飞书—— 调 /publish-to-lark $ACTIVE_REQ_DIR/prd.md --type prd
```

future skill（task-spec / analysis）类似集成。
