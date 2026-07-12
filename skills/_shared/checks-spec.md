# checks-spec（§7.C 统一引擎的数据格式）

> 一份机器可检的「页面应该有什么」清单。`scripts/checks-diff.py` 拿它 + 抓取产物对比出 P0/P1/P2。
> 三个消费场景共用同一格式、只换参照物：覆盖审计（参照=范围清单）/ 对齐线上 §7.B（参照=线上真实产品）/ 站点爬 §7.A（参照=目标站）。
> 吸收自 PM 雏形 `prototype-live-align` 的 `<module>.json` 契约。**checks 不让 PM 手写 JSON** —— 由三条上坡路 / 爬取 AI 辅助派生。

## checks-spec JSON

```json
{
  "schema_version": "1.0",
  "module": "<模块/需求短名>",
  "reference_base_url": "https://线上或目标站（站点爬/对齐线上用；覆盖审计可空）",
  "local_base_url": "http://localhost:<prototype dev 端口>",
  "checks": [
    {
      "id": "<唯一 id，如 knowledge_l1>",
      "level": "L1",                       // L1 一级页 / L2 二级 / L3 三级
      "kind": "page",                      // page / modal（弹窗）
      "reference_path": "/线上路由（覆盖审计可空）",
      "local_path": "/prototype 路由",
      "must_have_text": ["必须出现的文案", "..."],
      "must_check_buttons": [
        { "text": "新建", "disabled": false },
        { "text": "删除", "disabled": true }
      ],
      "must_cover_states": ["loading", "empty", "success", "error"],
      "notes": "一句话备注"
    }
  ]
}
```

## 抓取产物（caller 用 gstack `/browse` 抓）

每个 check 抓两份（覆盖审计可只抓 local），放进 `<artifacts>/{reference,local}/<check_id>.json`，最小字段：

```json
{ "url": "...", "title": "...", "textPreview": "页面可见文本", "buttons": [ { "text": "...", "disabled": false } ] }
```

## 跑 diff

```bash
python3 "$PMAI_HOME/scripts/checks-diff.py" \
  --plan <checks-spec.json> --artifacts <artifacts-dir> \
  --report <report.md> [--todo <patch_todo.md>] [--fail-on-p0]
```

判级：本地按钮缺失 / 禁用态错 = **P0**；文案缺失 / 参照与本地按钮态不一致 = **P1**；状态覆盖（需人工演示确认）= **P2**。

## 边界

- 引擎只查**结构 / 文案 / 按钮态**（机器可判的）。**视觉细则**（sticky / 横滚 / 禁 native `alert`·`confirm` 用包装组件 / 留白密度 / 四态覆盖的样子）照 `DESIGN.md` + 模块规格，进入 acceptance profile 选中的 visual 检查，不在本引擎。
- `must_cover_states` 引擎只提醒「去演示确认」，不自动判（状态切换是行为，归行为审 `/browse`）。
