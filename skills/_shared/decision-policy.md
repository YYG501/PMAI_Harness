# Decision policy（PMAI 共用）

design、meta、mockup、spec-writing、build 和自动收尾共用这一套决策分类。目标是只让 PM 回答会改变产品方向或授权不可逆动作的问题，其余判断由 AI 承担并在自然收口点汇总。

| 类别 | 判据 | 默认处理 |
|---|---|---|
| `mechanical` | 路径解析、格式修正、已有规则的直接应用、可由仓库事实唯一推出 | 后台自动处理，不提问 |
| `reversible/taste` | 可快速撤回的命名、局部密度、实现细节、没有改变产品对象和规则的偏好 | AI 给推荐并推进，在本轮自然收口点汇总 |
| `product-model fork` | 会改变对象、责任、状态、权限、真相源、业务规则、页面任务或成功标准 | 立即停住，让 PM 拍一个真实岔路 |
| `one-way door` | merge、破坏性删除、数据迁移、外部发布、安全例外、不可逆授权 | 执行前立即确认；PM 明确说“可以提交 / 合并 / 发布”等即是该动作授权，不再二次确认 |
| `user challenge` | AI 想改变 PM 已明确选择或已生效决定 | 先给证据、反例和代价；PM 原方向继续有效，除非 PM 明确改选 |

## 判断顺序

1. 先查 context pack 和当前文件，能由事实回答的归 `mechanical`。
2. 再问“这会不会改变产品模型或用户行为”。不会且可撤回，归 `reversible/taste`。
3. 会改变对象、责任、状态、权限、真相源或成功标准，归 `product-model fork`。
4. 无论产品模型是否已定，只要动作不可逆，归 `one-way door`。
5. AI 若在反对 PM 已明确方向，额外标为 `user challenge`，不能把自己的建议伪装成未决问题。

## 问句不是决定

- `discussion.md` 中的问号、TODO、假设、AI 推荐、未被回答的选项都不能写进 active decisions 或规范性规格。
- 新决定必须能指向 PM 的明确回答，或 PM 明确接受 AI 推荐的语句。
- 推翻旧决定时在 `decisions.md` 标明 supersede 关系；`spec.md` 直接改成当前事实，不保留删除线和旧正文。

## 提问合同

只在 `product-model fork`、`one-way door`、`user challenge` 三类立即打断。题目必须说明：

- 这次具体要拍什么；
- 两个方向各改变什么业务结果；
- AI 的默认建议及依据；
- 不回答时为什么不能安全继续。

不要把每个 finding 拆成一道题，也不要问 PM 是否调用 meta、mockup、spec-writing、worktree 或执行器；这些是框架内部编排。
