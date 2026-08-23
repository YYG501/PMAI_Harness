# Grill 方法与 PMAI 的适配边界

PMAI 使用 `vendor/mattpocock-skills/` 中固定版本的上游方法作为 Design 的访谈内核。这里记录的是适配规则，不是第二套生命周期。

## 概念映射

| 上游概念 | PMAI 落点 |
|---|---|
| design tree | Design 后台维护的产品决定依赖关系 |
| frontier | 当前所有前置条件已明确、可以独立回答的问题 |
| round | 一个 `decision-gate.py open-round` 登记的展示批次 |
| question | 一个独立的产品模型决定，单独消费到 D 编号 |
| shared understanding | frontier 为空后，PM 对共识摘要的明确确认 |
| domain modeling | `discussion.md` 中的术语、对象关系和边界场景；稳定决定进入 `decisions.md` |
| prototype | `/pmai-mockup` 或对应原型能力，用来验证文字无法判断的逻辑 / UI 问题 |
| to-spec | PMAI 自己的 `/pmai-spec-writing`，不重新访谈 |

## 运行规则

1. 事实由 Agent 调查，不能把能从代码、文件、测试和上下文查到的内容交给 PM。
2. 只有会改变对象、责任、状态、权限、真相源、页面任务或成功标准的真实岔路进入 frontier。
3. 同一 frontier round 可以包含多个互不依赖的问题；依赖本轮其它问题的题目必须留到下一轮。
4. 一条用户消息可以回答同轮多个问题，但 Agent 必须通过 `answer-round --selection` 或 `--free-text` 显式列出每个已回答问题；未列出的题继续 pending。
5. 每个问题仍有独立 gate、推荐答案、答复事件、D 编号和消费记录。round 不是把多个产品决定合并成一个决定。
6. frontier 为空后还要取得 PM 的 shared-understanding 确认；确认前不能写最终规格、提交建造依据或进入 build。

机器收据顺序：

```text
open-round → observe → answer-round
本轮全部回答 → 逐题写 decisions.md → 逐题 consume → 重新计算 frontier
frontier 清空 → open-shared → observe → confirm-shared → consume-shared
→ 写入/提交 spec → ready
```

`shared-understanding` 是独立的非产品收据，不产生 D 编号，也不替代 `decisions.md`。`spec.md` 的写入门、staged 检查和 `ready` 都要求它已被消费；`ready` 还会把它绑定到当前 design checkpoint。

## 不带入上游的内容

PMAI 不复制上游的 issue tracker、ADR / glossary 文件布局或用户入口。Proposal 合同、模块三件套、context pack、项目建造定义、ready / build / lark-review 仍以 PMAI 文件和脚本为唯一真相源。
