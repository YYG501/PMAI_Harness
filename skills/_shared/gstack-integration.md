# PMAI 与 gstack 结合合同

> **核心边界**：PMAI 是产品工作流、真相源和收口门禁；gstack 是消费仓里可直接调用的专项能力层。PMAI 可以在明确节点调用 gstack skill，但 gstack 输出必须接回 PMAI 自己的记录位置，不能把 `~/.gstack/...` 当长期真相源。

gstack 在项目初始化阶段不是依赖。是否需要页面验收由 design 生成的 `.pm-workflow/project.yml:web.enabled` 和本轮目标决定；一旦 adaptive acceptance 选中 Web 检查，主动浏览器能力就是硬要求，但证据生产者不限定只能是 gstack。

## 一、四种结合方式

### 1. 方法吸收

适用：PMAI 吸收 gstack / office-hours / grillme 的方法素材，但不运行 gstack，不把外部方法当 PMAI 主品牌。

- `/pmai-meta` 的最终产物是 PMAI 自己的**产品判断模型**：判断句、地基账本、判断标准、模型轴、分路。gstack / office-hours 提供需求证据、现状对手、具体用户、最小切口、观察意外、未来适配等产品想法素材；grillme 提供一题一问、沿依赖决策树、推荐默认答案、短答追问、能从文件查到的不问 PM 等问法纪律。
- `/pmai-meta` 不 runtime 调 gstack，不把 office-hours / grillme 作为 PMAI 主品牌，不把 gstack 输出当 PMAI 真相源。
- PM 视图规则可借鉴 banner、Next Up、Decision gate pattern。
- 输出必须用 PMAI 的业务语言，不把外部方法名当成前台流程。

### 2. 能力调用

适用：gstack 已有专项 skill 比 PMAI 自建更稳，PMAI 只定义输入、调用时机和接回路径。

- `/design-consultation`：用于项目视觉基线，写入或补全 `DESIGN.md` 的视觉段；PMAI 仍负责框架 inventory 和 build 约束。
- `/design-shotgun`：用于 mockup 视觉探索；PMAI 先定产品方向，gstack 出多版，最后导回 `mockups/manifest.json`。
- `/setup-browser-cookies`、`/browse`、`/scrape`：用于参考站 / 线上产品抓取；结果落 `.pm-workflow/mirror/`，由 PMAI checks-diff 接住。
- `/make-pdf`：用于把 PMAI 生成的 Markdown 导出为 PDF；源 Markdown 仍是长期记录，PDF 只是交付格式。

### 3. 自适应证据生产

适用：gstack / browser 产出检查证据，PMAI 决定能不能收口。

- acceptance profile 选中 `browser-smoke / visual / behavior` 时，AI 先解析当前 runtime 的主动浏览器适配器：优先 gstack `/browse`，也可使用可实际操作页面的 browser 或 Playwright 能力，不把工具选择交给 PM。
- 使用 gstack 时可运行 `check-gstack-browser.sh --browser-smoke --json-out .pm-workflow/audits/<模块>/browser-smoke.json`；其它适配器必须产出同一 PMAI evidence contract。
- `browser-smoke` 只有 `status=pass` 且 artifact 含 `active_browser_smoke=true` 才有效。不能用 exception 跳过主动浏览器能力；没有任何适配器时 UI final_check 直接阻塞。
- `/design-review` 或等价视觉能力产出 visual evidence；`/browse`、browser 或 Playwright 产出 behavior evidence。PM 请求定稿后，每项都由 final-lane `record-evidence` 绑定 source hash 和 implementation commit。
- 非 Web product build 不生成浏览器检查；工具是否必需由 acceptance profile 决定，不由初始化是否安装 gstack 决定。
- 统一 final_check 只认 PMAI build contract。`/pmai-build-close` 兼容恢复复用同一合同。

### 4. 可选旁路

适用：PM 主动想要第二视角、工程文档或额外复审；不进入 PMAI 默认门禁。

- `/qa`、`/qa-only`、`/review`：额外复审或 QA，不替代 acceptance profile 选中的 final checks。
- `/plan-ceo-review`、`/plan-design-review`、`/plan-eng-review`、`/plan-devex-review`：方案第二视角，结果需要 PM 逐条拍。
- `/document-generate`：工程文档生成旁路，只用于 README、API、CLI、架构说明、how-to、tutorial、reference；不用于产品介绍、PRD、模块规格或 PM 汇报材料。
- `/document-release`：post-ship 工程文档同步旁路，不替代 landed 后 PMAI 产品真相源编译。

## 二、旁路文档接回协议

`/document-generate` 和 `/document-release` 是工程文档旁路，不是 PMAI 产品文档主流程。

- 产品介绍、功能清单、优势说明、一页纸、PM 汇报材料 → 转 `/pmai-doc-writing`，默认落 `docs/deliverables/`。
- PRD、功能需求、功能描述、功能规格、功能评审稿、模块规格 → 转 `/pmai-spec-writing` 或 `/pmai-design`，默认落 `docs/modules/`。
- README、API、CLI、架构说明、how-to、tutorial、reference → 可采用 gstack 旁路结果，接回 `docs/engineering/`，并登记 `docs/engineering/INDEX.md`。
- gstack 旁路结果只有落入消费仓文档地图并补索引后，才算 PMAI 已接收；只引用 `~/.gstack/...`、浏览器下载目录或临时路径不算接收。
- 老消费仓没有 `docs/engineering/INDEX.md` 时，首次采用工程文档要按 `$PMAI_HOME/templates/engineering-INDEX.md.tmpl` 补建。

## 三、接回规则

- gstack 设计稿必须复制进 `mockups/` 并登记到 `mockups/manifest.json`。
- gstack 视觉 / 浏览器检查必须写成 PMAI 约定的 evidence artifact，再由 `build-contract.py record-evidence` 绑定到当前实现。
- gstack 抓站结果必须落进 `.pm-workflow/mirror/`，由 `checks-diff.py` 生成 report / patch todo。
- `/make-pdf` 生成的 PDF 不能反向覆盖源 Markdown；源 Markdown 仍在 `docs/deliverables/` 或对应 PMAI 文档位置。
- gstack 工程文档如果被采用，必须落进 `docs/engineering/`，更新 `docs/engineering/INDEX.md`，并遵守消费仓文档地图。

## 四、禁止事项

- 不新增 `/pmai-gstack` 或 `/pmai-office-hours`。
- 不把 gstack skill 复制、改写或 vendoring 进 PMAI。
- 不给 gstack skill 加 `pmai-` 前缀；消费仓里直接使用裸 skill 名。
- 不把 `/spec` 接入 PMAI 主链路，避免和 `/pmai-design`、`/pmai-spec-writing`、模块三件套冲突。
- 不让 gstack 输出绕过 PMAI 的 PM 拍板、真相源和收口门禁。
