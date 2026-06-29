# /pmai-meta 与 /pmai-doc-writing 职责归位反馈（2026-06-28）

<!-- 状态：已消化（2026-06-28，未提交；当前工作区有并行改动，未生成 commit hash） -->

## 原始反馈

- “媒体标题 / 定位句生成（重模式）这个内容，为啥在这个 skill 里面”
- “而且我还在想，这个 skill，为什么需要词表和句式”
- “你仔细看一下，句式这个文件中，其实应该是放了一些术语，还有一些有用的东西”
- “看看是不是有些东西也可以放进 doc-writing 里面”

## 消化结果对账表

| # | 反馈类目 | 落地状态 | 现状位置 | 剩余 gap |
|---|---|---|---|---|
| 1 | `/pmai-meta` 不应承担媒体标题 / 定位句生成 | 已落地 | `skills/meta/SKILL.md` 输出段；`skills/meta/references/词表与句式.md` | 无。meta 只产出重定位结论、判断标准和落地含义。 |
| 2 | `词表与句式` 不是单纯句式库，包含有用术语和校验工具 | 已落地 | `skills/meta/references/词表与句式.md` | 无。保留禁用词、各域判断标准词库、从 A 到 B、旧范式校验。 |
| 3 | 一句话定位 / 标题成文应归 `/pmai-doc-writing` | 已落地 | `skills/doc-writing/SKILL.md`；`skills/doc-writing/references/product-direction.md` | 无。doc-writing 承接标题、定位句、页首主张成文规则。 |
| 4 | `/pmai-meta` 与 `/pmai-doc-writing` 的交接关系要清楚 | 已落地 | `skills/meta/SKILL.md`；`skills/doc-writing/references/product-direction.md` | 无。doc-writing 可吸收 meta 的重定位结论，但最终由 doc-writing 成文。 |

