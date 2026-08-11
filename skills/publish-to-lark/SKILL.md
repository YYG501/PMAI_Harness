---
name: pmai-publish-to-lark
description: 将本地 Markdown 发布或更新至飞书云文档。首次发布创建文档；已有文档默认精细更新并保留飞书图片、评论、白板、附件和复杂格式，只有 PM 明确要求时才整篇覆盖。发现飞书侧有独立变化时转 pmai-lark-review。
---

# /pmai-publish-to-lark

## 入口护栏

执行本 skill 前先运行：

```bash
source "${PMAI_HOME:-$HOME/.pmai}/scripts/skill-preamble.sh"
```

如果输出 `PMAI_PROJECT_INITIALIZED: 0`，停止本 skill，只引导 PM 先发 `/pmai-init-project`。初始化或已有代码接入完成前，不要读取项目发布配置、写 frontmatter 或覆盖飞书文档。

## When To Use

- PM 要把本地规格、PRD 或介绍型文档发布、更新或重新发布到飞书
- PM 明确提出“精细写回”“更新飞书但不要丢图片 / 评论 / 白板 / 附件”
- 由 spec-writing 或 doc-writing 在文档完成后调用
- PM 手动调用：`/pmai-publish-to-lark <markdown 路径> [--type <type>] [--target-token <token>] [--title <title>]`

以下情况不用本 skill：

- PM 已明确以飞书为准、只要机械同步回本地：用 `/pmai-sync-from-lark`。
- PM 在飞书 review、修改正文或添加批注，并希望影响规格、决定、原型或实现：用 `/pmai-lark-review`。
- 只说“我在飞书改了”，但没有明确放弃产品影响判断：默认进入 `/pmai-lark-review`。

## 公开职责与内部策略

本 skill 只表达一个 PM 意图：**把本地内容发布到飞书**。首次创建、精细更新和整篇覆盖是内部执行策略，不再要求 PM 选择另一个同步 Skill。

- 没有 `lark_doc_id`：首次创建整篇文档。
- 已有绑定且远端仍等于最后对齐基线：默认按 `skills/_shared/lark-writeback.md` 精细更新。
- PM 明确说“整篇覆盖 / 重新发布 / 本地为准全部替换”：才允许调用 overwrite 执行器。
- 远端 revision 已前进、基线缺失或双方都变化：零写入并转 `/pmai-lark-review`，不得猜测哪边应覆盖。

发布完成后如果 PM 在飞书正文中修改或添加批注，并要求更新本地规格和原型，使用 `/pmai-lark-review`。不要用本 skill 再次 overwrite 掩盖评审结果。

`/pmai-lark-review` 会直接使用同一个内部精细写回合同，不反向调用本公开 Skill。

## Required Inputs

1. `markdown_path`：要发布的 markdown 文件路径；优先用仓内相对路径，仓外文件才用完整路径
2. `--type`（可选）：文档类型，决定默认目标位置和命名规则（`prd` / `spec` / `other`）
3. `--target-token`（可选）：覆盖默认目标位置（wiki node token 或 folder token）
4. `--target-kind`（可选）：`wiki` 或 `folder`，与 `--target-token` 配套
5. `--title`（可选）：覆盖默认标题
6. `--no-merge-cells`（可选）：首次创建或整篇覆盖时跳过表格合并（默认开启合并）

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

首次发布且未配置类型时，PM 必须同时传 `--target-token` + `--target-kind` + `--title`，否则 skill 报错退出。已有文档更新沿用原绑定位置，不要求重复提供目标配置。模板见 `$PMAI_HOME/templates/lark-publish.json.tmpl`。

`title_template` 占位符从 markdown frontmatter 或文件名读取（`{module}` / `{filename}`）。默认 PRD 发布使用 `{module} PRD`；没有 `module` frontmatter 时，手动传 `--title` 或把模板改成 `{filename}`。

## 必读 References

- `skills/_shared/lark-writeback.md`
- `skills/_shared/lark-document-verification.md`

## Preflight Check（首次创建 / 整篇覆盖脚本自动执行）

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
- **有** → 绑定已有文档，进入更新策略判断
- **无** → 走"首次发布"分支

已有绑定时先拉取飞书 full 内容和当前 revision，并读取本地 `lark_published_revision_id` / `lark_published_source_hash`：

- 远端 revision 等于最后对齐基线，本地正文变化 → 默认精细更新。
- 远端 revision 与基线不同，或缺少可验证基线 → 停止并转 `/pmai-lark-review`。
- 本地正文没有变化 → 不写飞书，直接报告已经对齐或远端存在待评审变化。
- PM 明确授权整篇覆盖 → 仍先绑定写前 revision，再进入覆盖策略；授权不能绕过文档身份和并发栅栏。

### 步骤 2：首次发布时决定目标位置 + 标题

按以下优先级：

1. 命令行参数 `--target-token` + `--target-kind` + `--title`（最高）
2. `.claude/lark-publish.json` 中 `--type` 对应的配置
3. 都没有 → 报错退出，提示 PM 配置或手动传参

已有文档更新不重新选择 wiki / folder 位置。

### 步骤 3：执行发布策略

**首次发布或 PM 明确整篇覆盖：**调用 `python3 "$PMAI_HOME/scripts/publish-to-lark.py"` 执行创建 / overwrite 编排。

发送给飞书前，会自动剥掉 markdown 开头的 YAML frontmatter（`---` 包裹的元数据块），
只发正文 —— 飞书不识别 frontmatter，不剥会把它当一段正文渲染。adapter 先把源文件
绑定为稳定的普通文件快照，再通过受控 stdin（`--content -`）发送正文；不会创建可被并发
换名或替换的临时 markdown。子进程 cwd 仍绑定源文件目录身份，保留相对资源解析基准。
覆盖发布尤其必然带 frontmatter（首次发布回填的 `lark_doc_id` 等就在 frontmatter 里）。

**首次发布：** adapter 调用 `docs +create`，传 `--title`、目标 wiki node 或 folder token、
`--content -` 和 `--doc-format markdown`；剥离后的正文由 adapter 直接写入子进程 stdin。
用户和调用方不要绕过 `publish-to-lark.py` 自行拼 lark-cli 命令或 shell 管道。

拿到返回的 `document_id`。

**整篇覆盖：** adapter 调用 `docs +update`，传现有文档 ID、`--content -`、
`--doc-format markdown`、`--command overwrite` 和写前 revision；正文仍只走同一受控 stdin。
只有 PM 明确授权整篇覆盖时，公开 Skill 才能进入这个脚本分支。

**已有文档默认更新：**直接按 `skills/_shared/lark-writeback.md` 执行精细写回。不得为了复用执行步骤调用其它公开 Skill，也不得退化成 Markdown overwrite。写回后按共享验收合同回读并刷新对齐基线。

### 步骤 4：首次创建 / 整篇覆盖时自动合并表格 cell（默认开启）

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

精细更新保留现有原生表格，不运行整篇发布后的启发式合并。

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

**每次成功创建、精细更新或覆盖**都使用明确的 base revision，并在写入完成后 fetch 当前文档。只有 document ID 正确、写操作返回了 revision，且回读 revision 仍等于该写入 revision 时，才原子更新：

```yaml
lark_published_revision_id: 12
lark_published_source_hash: <规范化本地正文 SHA-256>
```

这两个字段共同定义 `/pmai-lark-review` 的发布基线。飞书 Markdown 导出会重新转义，不能用导出文本与本地源文本近字节相等判断并发。写入 revision 缺失、文档身份不一致、回读 revision 已前进，或发布后本地正文又变化时，飞书发布本身保持成功，但清除旧基线、不写一半基线，并明确警告后续评审将按旧文档降级；不能把发布窗口内的新版本与另一份本地正文配成一对。

### 步骤 6：完成

输出：

```text
飞书文档已发布或更新
URL: https://xxx.feishu.cn/docx/doxcnxxxxxx
内容变化：<首次创建 / 精细更新 / 明确整篇覆盖及变化摘要>
校验结果：<已回读一致；保留内容未受影响 / 未通过及原因>
需要你处理：<无需处理 / 需要进入飞书评审的具体变化>
```

执行协议和追踪字段只用于内部校验与恢复，不进入正常 PM 回执。

## Rules

- **方向固定**：本 skill 只处理本地到飞书；飞书到本地使用 `/pmai-sync-from-lark` 或 `/pmai-lark-review`
- **默认精细更新**：已有文档的“发布 / 更新飞书”默认保留原生内容，不等于 overwrite
- **覆盖发布需明确意图**：只有用户明确说“覆盖 / 重新发布 / 本地为准全部替换”才允许整篇覆盖
- **远端变化进入评审**：基线缺失、远端 revision 已前进或双方变化时零写入，转 `/pmai-lark-review`
- **合并是 fail-soft**：合并失败不阻塞主发布；首个表格写入失败后停止剩余合并，避免在未知 revision 上继续写，只输出警告与失败计数
- **merge cell 判定（前 N-1 列）**：非空 anchor 吸收下方相同内容 cell + 下方空 cell（续行 rowspan 语义）；range > 1 行才合并
- **merge cell 判定（末列 / 需求描述）**：识别续行 row group（前 N-1 列全空的连续行），先把非锚点 cell 的 children blocks 拷贝到锚点 cell，删原 cell children，再 merge_table_cells；保留富文本格式
- **`<!-- lark:no-merge -->` 标记**：markdown 表前加此注释 → 该表跳过启发式合并、原样发布。权限矩阵等「数据表」（空格 = 无数据、不是续行）必用，否则空格会被错误合并
- **HTML `<table>` 预检**：正文含裸 HTML `<table>` → 发布时打印警告 + 行号（飞书只认 GFM 管道表格，HTML 表会被压成纯文本、结构全丢）；警告不阻断发布
- **文档身份回填**仅首次发布执行；覆盖发布不改 `lark_doc_id` / URL / 首次发布时间
- **评审基线刷新**每次成功发布后都尝试执行；只有写入 revision 与回读 revision 一致、且本地正文仍是本次发送版本时才写入，`lark_published_revision_id` 和 `lark_published_source_hash` 必须同时更新或同时清除
- **覆盖写入带 revision 栅栏**：`docs +update` 必须携带写前 revision；冲突时停止，不用 latest 重试覆盖
- **发送时剥离 frontmatter**：发给飞书的内容只含正文，开头的 YAML frontmatter 会被剥掉（飞书不识别 frontmatter，不剥会渲染成正文）；剥离只作用于发送内容，本地 markdown 文件不动
- **正文只走 adapter stdin**：发布命令固定使用 `--content -`，正文由已绑定源文件的内存快照写入 stdin；禁止退回 `@file` 临时文件或由调用方拼裸 shell 管道
- **不修改正文**：除 frontmatter 外，本 skill 不改 markdown 任何内容
- **不做 wiki/folder 切换**：首次发布的目标位置一旦定下，覆盖发布只能在同位置；要换位置必须删 frontmatter 中的 `lark_doc_id` 后重新首次发布

## Failure Handling

| 错误类型 | 处理 |
|---|---|
| 配置缺失 | 提示 PM 编辑 `.claude/lark-publish.json` 或手动传 `--target-token` + `--target-kind` + `--title` |
| lark-cli 认证失败 | 提示 PM 跑 `lark-cli auth login`（参考 lark-shared skill）|
| 创建文档失败 | 报错并退出，不进入合并步骤 |
| 远端 revision 已前进或基线不可验证 | 零写入，转 `/pmai-lark-review` |
| 精细更新无法生成安全的最小操作 | 停止，不扩大修改范围；报告需要判断的区段 |
| 覆盖文档失败 | 报错并退出，frontmatter 不动 |
| 拉 block 列表失败 | 警告并跳过合并；主发布仍算成功 |
| 单次合并 cell 失败 | 警告并停止后续合并写入；主发布仍保持成功，避免 revision 串联错位 |
| frontmatter 写入失败 | 报错，但飞书侧文档已发布成功，提示 PM 手动回填 URL |
| 发布后 revision 读取失败 | 警告，发布保持成功；不写不完整评审基线，后续 review 按 legacy 规则处理 |
| 发布后回读身份 / revision 不一致 | 警告，发布保持成功；清除旧基线，保留差异供 lark-review 判断 |

## 集成示例

spec-writing 在沉淀阶段结束模板加：

```markdown
D) 发布到飞书—— 调 /pmai-publish-to-lark docs/modules/<按内容命名>.md；首次创建或对已有文档做默认精细更新
```

future skill（spec 等 PM 视图文档）类似集成。
