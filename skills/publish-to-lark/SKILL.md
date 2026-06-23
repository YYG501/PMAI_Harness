---
name: pmai-publish-to-lark
description: 把本地 markdown 文档发布到飞书云文档，发布后自动合并表格中相邻相同内容的 cell。首次发布回填飞书 URL 到 markdown frontmatter，下次按 URL 覆盖原文档。通用发布编排层，被 prd-writing 等 skill 调用；PM 也可手动 `/pmai-publish-to-lark <markdown 路径> [--type prd|analysis|other]`。
---

# /pmai-publish-to-lark

## When To Use

- 由 prd-writing 在沉淀阶段结束模板调用（D 选项），用于发布当前工作 PRD
- 未来可被 analysis 等其它 skill 复用
- PM 手动调用：`/pmai-publish-to-lark <markdown 路径> [--type <type>] [--target-token <token>] [--title <title>]`

## Required Inputs

1. `markdown_path`：要发布的 markdown 文件绝对路径
2. `--type`（可选）：文档类型，决定默认目标位置和命名规则（`prd` / `analysis` / `other`）
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
    "analysis": {
      "kind": "wiki",
      "token": "wikxxx...",
      "title_template": "{req_id} 需求分析"
    }
  }
}
```

未配置类型时，PM 必须同时传 `--target-token` + `--target-kind` + `--title`，否则 skill 报错退出。模板见 `$PMAI_HOME/templates/lark-publish.json.tmpl`。

`title_template` 占位符从 markdown frontmatter 或文件名读取（`{req_id}` / `{req_title}` / `{module}` / `{filename}`）。

## Preflight Check（脚本入口自动执行）

调用 `publish-to-lark.py` 时，脚本头部统一做以下 5 项检查，任一失败即明确报错并退出，不进入实际发布：

| 检查项 | 失败时提示 |
|---|---|
| `lark-cli` 在 PATH | `lark-cli 未安装。安装方式见 https://github.com/larksuite/lark-cli` |
| `lark-cli --version` ≥ `1.0.14` | `lark-cli 版本 <实际值> 低于最低要求 1.0.14；请升级` |
| `lark-cli auth status` 已登录 | `飞书 CLI 未登录。运行 lark-cli auth login（详见 lark-shared skill）` |
| `lark-cli auth check --scope` 关键 scope 已授权 | `缺少 scope: <list>；请在飞书开放平台为 app 申请 scope 后重新 lark-cli auth login` |
| `.claude/lark-publish.json` 存在 或 命令行参数齐全 | `配置缺失。复制 $PMAI_HOME/templates/lark-publish.json.tmpl 到 .claude/lark-publish.json 并填 token；或手动传 --target-token + --target-kind + --title` |

**版本基线说明：** 1.0.27 是当前已验证的工作版本（1.0.27 把 scope 名称从粗粒度改为细粒度）。lark-cli 后续如发版引入 breaking change，更新本文件并 bump 此版本号。

**关键 scope（lark-cli ≥1.0.27 精确名称）：** 发布到 wiki 时 `docx:document:write_only` + `wiki:node:retrieve`；发布到 folder 时 `docx:document:write_only` + `drive:file:upload`；合并 cell 还需 `docx:document:write_only`。脚本按目标位置类型动态决定要检查的 scope 列表。

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

调用 `python3 "$PMAI_HOME/scripts/publish-to-lark.py`" 执行编排。

发送给飞书前，会自动剥掉 markdown 开头的 YAML frontmatter（`---` 包裹的元数据块），
只发正文 —— 飞书不识别 frontmatter，不剥会把它当一段正文渲染。本地 markdown 文件不动。
覆盖发布尤其必然带 frontmatter（首次发布回填的 `lark_doc_id` 等就在 frontmatter 里）。

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

### 步骤 4：自动合并表格 cell（默认开启）

> **逐表跳过（`<!-- lark:no-merge -->`）**：markdown 里某张表的紧邻上文若有 `<!-- lark:no-merge -->` 注释，该表整张跳过合并、原样发布。用于权限矩阵这类「数据表」—— 空单元格表示「无权限 / 无数据」而非「续行」，不能被启发式合并吞掉。脚本按表格出现顺序与文档侧 table block 下标对齐；数量对不上则忽略全部标记并警告。

发布完成后，扫描文档中所有 table 块。合并按"前 N-1 列（leading）"和"末列（需求描述）"分两段处理：

1. `GET /open-apis/docx/v1/documents/:doc_id/blocks` 拉所有 block
2. 找出所有 `table` block；构建 `grid[row][col]` 文本矩阵；提取已有 `merge_info` 的 cell 集合作为跳过名单
3. **前 N-1 列合并**（leading 列 rowspan）：对每一列从上到下扫描，遇非空 anchor 后吸收**下方所有相同内容 cell + 下方所有空 cell**，直到遇到下一个非空异内容或表格末尾。range > 1 行才合并。空 cell 是"续行 rowspan 标记"，参与合并到上方非空 cell。
4. **末列合并**（需求描述列内容拷贝合并）：扫描续行 row group——anchor 行（任一前 N-1 列非空）+ 下方所有续行（前 N-1 列全空）。group 多行时：
   - 把每个非锚点 cell 的 children blocks 反序列化为 creation spec（保留 `block_type` + `text/heading/code` 等字段，含 `elements` 富文本格式）
   - `POST /blocks/:anchor_cell_id/children` body `{"children": [...specs...], "index": <锚点当前 children 数量>}` 一次性追加所有非锚点的 child blocks 拷贝到锚点 cell 末尾
   - `POST /blocks/:non_anchor_cell_id/children/batch_delete` body `{"start_index": 0, "end_index": <非锚点 children 数量>}` 清空原 cell 的 children（Feishu batch_delete 是 POST + 索引区间，不是 DELETE + ID 列表）
   - `PATCH /blocks/:table_id` with `merge_table_cells` 合并 cells
5. 跳过已存在 `merge_info` 的 cell（避免重复合并）
6. 失败 fail-soft：单次合并失败不阻塞其它合并，最后输出失败计数

**为什么末列要拷贝内容再合并**：Feishu `merge_table_cells` API 只设置 cell 边界 row_span / col_span，被合并的非锚点 cell 内容会被遮蔽不显示。需求描述列的多行（"1. xxx" / "2. yyy" / ...）属内容不同的合并，必须先把非锚点的 children blocks 复制到锚点 cell（保留 `**bold**` / `` `code` `` 等富文本格式），再 merge，才能在飞书侧看到完整的多行编号列表。

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
- **merge cell 判定（前 N-1 列）**：非空 anchor 吸收下方相同内容 cell + 下方空 cell（续行 rowspan 语义）；range > 1 行才合并
- **merge cell 判定（末列 / 需求描述）**：识别续行 row group（前 N-1 列全空的连续行），先把非锚点 cell 的 children blocks 拷贝到锚点 cell，删原 cell children，再 merge_table_cells；保留富文本格式
- **`<!-- lark:no-merge -->` 标记**：markdown 表前加此注释 → 该表跳过启发式合并、原样发布。权限矩阵等「数据表」（空格 = 无数据、不是续行）必用，否则空格会被错误合并
- **HTML `<table>` 预检**：正文含裸 HTML `<table>` → 发布时打印警告 + 行号（飞书只认 GFM 管道表格，HTML 表会被压成纯文本、结构全丢）；警告不阻断发布
- **frontmatter 回填**仅首次发布执行；覆盖发布不动 frontmatter
- **发送时剥离 frontmatter**：发给飞书的内容只含正文，开头的 YAML frontmatter 会被剥掉（飞书不识别 frontmatter，不剥会渲染成正文）；剥离只作用于发送内容，本地 markdown 文件不动
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

prd-writing 在沉淀阶段结束模板加：

```markdown
D) 发布到飞书—— 调 /pmai-publish-to-lark $ACTIVE_WORK_DIR/prd.md --type prd
```

future skill（analysis 等）类似集成。
