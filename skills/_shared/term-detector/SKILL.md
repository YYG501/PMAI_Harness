---
name: _shared/term-detector
description: |
  landed 后的业务术语 / 角色结构化对账规则。只从规格、决定和 accepted deltas 中明确声明的术语与角色生成 PRODUCT.md 文档影响项。
---

# _shared/term-detector

> 内部共享能力，不是 PM 入口。`doc-impact.py init` 在实现 landed 后自动调用。

## 产品职责

模块工作中的临时词典留在 `spec.md` / 功能型规格的“名词解释”和“用户角色”表中。实现进入 main 后，本能力把已经稳定、但根 `PRODUCT.md` 尚未登记的业务术语和角色加入文档影响地图；它只报告差异，不直接改写长期真相源。

这一步解决的是跨模块复用问题：后续 design / build 能从 `PRODUCT.md` 继续使用已稳定的对象名称和角色定义，而不是每个模块重新命名。

## 候选来源

只接受可追溯的结构化声明：

1. 当前模块 `spec.md`、build 合同明确记录的规格锚点，以及本轮 landed diff 直接改动的模块 `spec.md` / 功能型规格中“名词解释 / 业务术语”表的术语列；
2. 上述规格中“用户角色 / 角色清单”表的角色列；
3. 当前模块 `decisions.md` 的有效 `D<number>` 决定中，单独一行声明的 `术语：<名称>` 或 `角色：<名称>`；
4. `accepted_deltas` 中 `kind=term` / `kind=role` 的条目。沿用现有 `add-delta` 合同，此时 `summary` 写准确名称。

不要扫描引号、加粗、普通正文或代码来猜术语。它们无法区分正式命名和修辞强调，也与规格统一使用 ASCII 引号的规则冲突。

## 对账顺序

1. 从脚本所在的 PMAI 安装目录（或显式 `PMAI_HOME`）读取 `whitelist.json`，不读取消费仓的 `skills/`；
2. 从消费仓根 `PRODUCT.md` 的“业务术语表 / 用户画像”读取已登记项；
3. 应用当前工作目录的可选 `.term-skip.json`；
4. 只把剩余的新术语 / 新角色交给 `doc-impact.py`，生成 `kind=term`、目标为 `PRODUCT.md` 的 pending 项；
5. 文档编译根据规格里的定义更新 `PRODUCT.md`，或说明无需更新后标记 `no-change`；`doc-impact.py validate` 前必须收口。

普通新名称如果已有清楚定义，AI 直接按现有决定和文档影响流程更新，不逐词打断 PM。缺少定义或会改变产品对象 / 角色模型时，才回到 design 让 PM 拍板，不能在 landed 收尾时猜。

## 调用

```bash
python3 "$PMAI_HOME/scripts/_lib/term-detector.py" \
  "$ACTIVE_MODULE_DIR" "$REPO_ROOT" \
  --work-dir "$ACTIVE_MODULE_DIR"
```

`doc-impact.py init` 会额外传入本轮 landed diff 中直接改动的模块 `spec.md` 和 `docs/modules/<按内容命名>.md` 功能型规格。`discussion.md`、`decisions.md` 与索引即使出现同名表格也不会作为规格来源；决定只按上面的显式 `D<number>` 声明读取。

返回示例：

```json
{
  "new_terms": ["结算批次"],
  "new_roles": ["平台审核员"],
  "skipped": ["旧叫法"],
  "whitelisted": ["用户"],
  "registered": ["商品池"],
  "candidates": [
    {
      "kind": "term",
      "name": "结算批次",
      "definition": "同一结算周期内的一组待结算订单",
      "source": "docs/modules/settlement/spec.md"
    }
  ]
}
```

## 边界

- 不在 design 探索中调用，不把未定稿用词提前升级为长期术语；
- 不从代码现状反推产品词典；
- 不新建第二套术语账本，长期真相仍是根 `PRODUCT.md`；
- 不向 PM 展示 detector、白名单、impact item 等后台名词，只说明需要补充或已更新的产品术语 / 角色。
