---
name: pmai-publish-to-lark
description: 将本地 markdown 文档整篇发布或覆盖至飞书云文档，发布后自动合并表格中相邻的相同单元格，并记录供后续飞书评审回收使用的 revision 与本地正文 hash。首次发布将飞书链接回写至文档，后续按链接覆盖更新。需要判断同步方向或保留飞书图片、评论、白板、附件时，先用 `/pmai-lark-sync`。
---

# /pmai-publish-to-lark

## 入口护栏

执行本 skill 前先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止本 skill，只引导 PM 先发 `/pmai-init-project`。初始化或已有代码接入完成前，不要读取项目发布配置、写 frontmatter 或覆盖飞书文档。

## When To Use

- 由 `/pmai-lark-sync` 判定为"整篇覆盖发布"后调用
- 由 spec-writing 在沉淀阶段结束模板调用（D 选项），用于首次发布 PRD 体例功能型规格文档
- 未来可被 spec 等其它 PM 视图文档复用
- PM 手动调用：`/pmai-publish-to-lark <markdown 路径> [--type <type>] [--target-token <token>] [--title <title>]`

## 与 `/pmai-lark-sync` 的关系

本 skill 是**整篇发布 / overwrite 执行能力**。它默认认为本地 markdown 是 source of truth，飞书只是发布面。

以下情况不要直接调用本 skill，先走 `/pmai-lark-sync` 判定同步方向：

- PM 说"同步飞书"、"更新飞书"，但没有明确允许覆盖
- 飞书在线文档可能已经被 PM 或协作者改成最终稿
- 需要保留飞书侧图片、评论、白板、附件或复杂表格
- 只想比较本地和飞书哪里不一致

发布完成后如果 PM 在飞书正文中修改或添加批注，并要求更新本地规格和原型，使用 `/pmai-lark-review`。不要用本 skill 再次 overwrite 掩盖评审结果。

## Required Inputs

1. `markdown_path`：要发布的 markdown 文件路径；优先用仓内相对路径，仓外文件才用完整路径
2. `--type`（可选）：文档类型，决定默认目标位置和命名规则（`prd` / `spec` / `other`）
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
      "title_template": "{module} PRD"
    }
  }
}
```

未配置类型时，PM 必须同时传 `--target-token` + `--target-kind` + `--title`，否则 skill 报错退出。模板见 `$PMAI_HOME/templates/lark-publish.json.tmpl`。

`title_template` 占位符从 markdown frontmatter 或文件名读取（`{module}` / `{filename}`）。默认 PRD 发布使用 `{module} PRD`；没有 `module` frontmatter 时，手动传 `--title` 或把模板改成 `{filename}`。

## Preflight Check（脚本入口自动执行）

调用 `publish-to-lark.py` 时，脚本头部统一做以下 5 项检查，任一失败即明确报错并退出，不进入实际发布：

| 检查项 | 失败时提示 |
|---|---|
| `lark-cli` 在 PATH | `lark-cli 未安装。安装方式见 https://github.com/larksuite/lark-cli` |
| `lark-cli --version` ≥ `1.0.27` | `lark-cli 版本 <实际值> 低于最低要求 1.0.27；请升级` |
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

调用 `python3 "$PMAI_HOME/scripts/publish-to-lark.py"` 执行编排。

发送给飞书前，会自动剥掉 markdown 开头的 YAML frontmatter（`---` 包裹的元数据块），
只发正文 —— 飞书不识别 frontmatter，不剥会把它当一段正文渲染。本地 markdown 文件不动。
覆盖发布尤其必然带 frontmatter（首次发布回填的 `lark_doc_id` 等就在 frontmatter 里）。

**首次发布：**

```bash
lark-cli docs +create \
  --title "<title>" \
  --wiki-node "<token>" \
  --content "@./<临时正文文件>" \
  --doc-format markdown
```

发布到文件夹时把 `--wiki-node` 换成 `--folder-token`。

拿到返回的 `document_id`。

**覆盖发布：**

```bash
lark-cli docs +update \
  --doc "<existing_doc_id>" \
  --content "@./<临时正文文件>" \
  --doc-format markdown \
  --command overwrite \
  --revision-id "<写前 revision>"
```

上述相对内容文件由 adapter 在临时目录生成并剥离 frontmatter；用户入口仍只调用 `publish-to-lark.py`，不要手工制造该文件。

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
6. 失败 fail-soft：单次合并失败不把主发布判为失败；由于后续写入必须串联前一笔 revision，首个写入失败后停止剩余合并，最后输出失败计数

**为什么末列要拷贝内容再合并**：Feishu `merge_table_cells` API 只设置 cell 边界 row_span / col_span，被合并的非锚点 cell 内容会被遮蔽不显示。需求描述列的多行（"1. xxx" / "2. yyy" / ...）属内容不同的合并，必须先把非锚点的 children blocks 复制到锚点 cell（保留 `**bold**` / `` `code` `` 等富文本格式），再 merge，才能在飞书侧看到完整的多行编号列表。

### 步骤 5：回填文档身份与评审基线

**首次发布**写入文档身份：

```yaml
---
lark_doc_id: doxcnxxxxxx
lark_doc_url: https://xxx.feishu.cn/docx/doxcnxxxxxx
lark_published_at: 2026-04-27T15:30:00+08:00
---
```

如果原文件已有 frontmatter，合并这三个 key（不动其它 key）；如果没有，创建一个新的。

**每次成功发布或覆盖**都使用明确的 base revision（首次创建读取 create 返回 revision；覆盖使用已有发布 revision，缺失时先 fetch），并在表格合并完成后 fetch 当前文档。只有 document ID 正确、写操作返回了 revision，且回读 revision 仍等于该写入 revision 时，才原子更新：

```yaml
lark_published_revision_id: 12
lark_published_source_hash: <规范化本地正文 SHA-256>
```

这两个字段共同定义 `/pmai-lark-review` 的发布基线。飞书 Markdown 导出会重新转义，不能用导出文本与本地源文本近字节相等判断并发。写入 revision 缺失、文档身份不一致、回读 revision 已前进，或发布后本地正文又变化时，飞书发布本身保持成功，但清除旧基线、不写一半基线，并明确警告后续评审将按旧文档降级；不能把发布窗口内的新版本与另一份本地正文配成一对。

### 步骤 6：完成

输出：

```text
飞书文档已发布
URL: https://xxx.feishu.cn/docx/doxcnxxxxxx
合并 cell: 成功 N 处 / 失败 M 处
本地 frontmatter: 已回填
评审基线: revision 12 / source hash abcdef123456
```

## Rules

- **单向同步**：本地 markdown 是 source of truth；飞书侧的修改下次发布会被覆盖
- **覆盖发布需明确意图**：如果用户只说"同步 / 更新"，不能默认调用本 skill；先用 `/pmai-lark-sync` 判断是精细同步、回拉、diff 还是覆盖
- **合并是 fail-soft**：合并失败不阻塞主发布；首个表格写入失败后停止剩余合并，避免在未知 revision 上继续写，只输出警告与失败计数
- **merge cell 判定（前 N-1 列）**：非空 anchor 吸收下方相同内容 cell + 下方空 cell（续行 rowspan 语义）；range > 1 行才合并
- **merge cell 判定（末列 / 需求描述）**：识别续行 row group（前 N-1 列全空的连续行），先把非锚点 cell 的 children blocks 拷贝到锚点 cell，删原 cell children，再 merge_table_cells；保留富文本格式
- **`<!-- lark:no-merge -->` 标记**：markdown 表前加此注释 → 该表跳过启发式合并、原样发布。权限矩阵等「数据表」（空格 = 无数据、不是续行）必用，否则空格会被错误合并
- **HTML `<table>` 预检**：正文含裸 HTML `<table>` → 发布时打印警告 + 行号（飞书只认 GFM 管道表格，HTML 表会被压成纯文本、结构全丢）；警告不阻断发布
- **文档身份回填**仅首次发布执行；覆盖发布不改 `lark_doc_id` / URL / 首次发布时间
- **评审基线刷新**每次成功发布后都尝试执行；只有写入 revision 与回读 revision 一致、且本地正文仍是本次发送版本时才写入，`lark_published_revision_id` 和 `lark_published_source_hash` 必须同时更新或同时清除
- **覆盖写入带 revision 栅栏**：`docs +update` 必须携带写前 revision；冲突时停止，不用 latest 重试覆盖
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
| 单次合并 cell 失败 | 警告并停止后续合并写入；主发布仍保持成功，避免 revision 串联错位 |
| frontmatter 写入失败 | 报错，但飞书侧文档已发布成功，提示 PM 手动回填 URL |
| 发布后 revision 读取失败 | 警告，发布保持成功；不写不完整评审基线，后续 review 按 legacy 规则处理 |
| 发布后回读身份 / revision 不一致 | 警告，发布保持成功；清除旧基线，保留差异供 lark-review 判断 |

## 集成示例

spec-writing 在沉淀阶段结束模板加：

```markdown
D) 同步到飞书—— 调 /pmai-lark-sync docs/modules/<按内容命名>.md，由它判断首次发布、精细同步、覆盖发布或只 diff
```

future skill（spec 等 PM 视图文档）类似集成。
