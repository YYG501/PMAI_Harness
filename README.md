# PM-AI-Workflow

PM-AI-Workflow（PMAI）是面向单人 PM 的 LLM 产品协作工作流生成器。

它把产品定位、模块设计、规格、原型或产品实现、反馈、验收和主线文档接成一条可恢复的协作链。PMAI 负责保存产品上下文和流程边界，PM 负责产品判断、看结果和明确定稿。

产品定位见 [`PRODUCT.md`](./PRODUCT.md)；当前进度、测试基线和后续工作见 [`RUNTIME.md`](./RUNTIME.md)。

## 3 分钟开始

PMAI 以全局 CLI 方式安装，一台机器安装一次，多个业务项目共用。

### 1. 安装

先确认 Python。PMAI 要求 Python 3.10 或更新版本，推荐 3.12；不要替换 macOS 自带的 `/usr/bin/python3`。macOS 使用 Homebrew 时：

```bash
brew install python@3.12 git node gh
export PATH="$(brew --prefix python@3.12)/libexec/bin:$PATH"
python3 --version
```

需要长期生效时，把同一条 `export PATH=...` 写入实际使用的 shell 启动文件，并重启 Claude Code 或 Codex。本仓为私有仓时，再使用有权限的 GitHub 账号安装：

```bash
gh auth status || gh auth login
rm -rf /tmp/pmai-src
gh repo clone YYG501/PMAI_Workflow /tmp/pmai-src
bash /tmp/pmai-src/bin/pmai install
~/.pmai/bin/pmai doctor --check
```

安装器会复用 `/tmp/pmai-src` 已认证的 `origin`，不会从 GitHub CLI 的 HTTPS 凭证切回未配置的 SSH。默认安装滚动版 `main`；稳定版发布后可把安装命令改为 `install --stable`。

### 2. 创建或接入业务项目

在任意业务项目目录中启动当前宿主的原生入口：

```text
Claude Code: /pmai-init-project
Codex:       $pmai-init-project
```

### 3. 推进第一个需求

```text
/pmai-proposal       新项目先澄清产品方向
/pmai-design         讨论模块、规则和关键交互
/pmai-build          查看结果、迭代并在确认后收尾
```

正常主链是：`init → proposal → design → spec-writing → build → finalize`。

## 常用入口

| 目标 | 入口 |
|---|---|
| 初始化或接入项目 | `/pmai-init-project` / `$pmai-init-project` |
| 澄清产品方向 | `/pmai-proposal` |
| 设计模块和行为 | `/pmai-design` |
| 生成或检查规格 | `/pmai-spec-writing` |
| 构建、预览、验收和收尾 | `/pmai-build` |
| 查看当前停点 | `/pmai-status`；用于忘记进度时恢复现场，它不是主流程的固定一步 |
| 只读检查框架和消费仓 | `/pmai-doctor` |
| 记录已确认的产品事实 | `/pmai-record` |
| 轻量修复 | `/pmai-quick-fix` |

## 安装与升级

```bash
pmai install --stable        # 首次安装最新稳定 tag
pmai install --to v0.1.0     # 首次安装指定 tag
pmai upgrade                 # 跟随 main 的滚动版本
pmai upgrade --stable        # 升级到最新稳定 tag
pmai upgrade --to v0.1.0     # 指定版本
pmai doctor --check          # 只读诊断
pmai uninstall               # 卸载全局安装
```

本地 checkout 也可以直接安装：`bash bin/pmai install`。安装成功会输出通道、tag 和实际 commit，便于复现。PMAI 只有全局安装模式；旧项目副本可用 `pmai uninstall --local <dir>` 清理。

## 宿主与依赖

- **Claude Code**：推荐的主控宿主，使用 `/pmai-*`；也可作为 `/pmai-build` 执行器。
- **Codex**：受支持的主控宿主，使用 `$pmai-*`、Skill 选择器或自然语言。Codex 作为当前主控时不重复进入外部候选。
- **OpenCode CLI**：仅作为 `/pmai-build` 的外部 Builder。
- **gstack / Playwright / runtime browser**：可选能力层；Web 项目的最终 UI 验收需要主动浏览器适配器，初始化和非 Web build 都不受阻塞。

基础依赖由 [`config/runtime-manifest.json`](./config/runtime-manifest.json) 维护：Python `>=3.10`（推荐 3.12）、Git `>=2.30`、Bash `>=3.2`；Node.js 是项目 Hook 的必需依赖，检查实际 API 与 Hook 语法兼容性，建议使用当前 LTS。gstack、飞书工具按需准备。安装器会在写入前检查当前环境，clone 后按目标版本再检查一次；安装和升级失败沿用既有回滚机制。

`pmai doctor --check` 检查安装态；`pmai doctor --check --json` 在 Python 完全缺失时仍返回结构化修复信息。开发仓可用 `python3 scripts/environment-check.py check --profile host` 单独检查环境。通过仅表示本地依赖满足检查条件，不代表宿主登录、模型调用或所有操作系统均已验证。Windows 说明见 [`docs/设计/windows-development-validation.md`](./docs/设计/windows-development-validation.md)。

不使用 GitHub CLI 时，可以先用已经配置好的 SSH 或 HTTPS 地址 `git clone`，再运行同一条 `bash /tmp/pmai-src/bin/pmai install`；安装器始终复用该 checkout 的 `origin`。`PMAI_REMOTE` 只用于明确覆盖来源。

需要复盘一次协作时，直接说“复盘这次对话”，无需选择内部命令。当前只有 Codex 的当前会话精确定位经过验证；其他宿主在没有可靠会话标识时会明确阻断，不会按最近修改时间猜测。

## 维护者入口

框架源文件位于 `skills/`、`scripts/`、`templates/` 和 `hooks/`。修改这些目录时，请同步评估 [`CHANGELOG.md`](./CHANGELOG.md) 的“未发布”段。

```bash
bash tests/run-all.sh
pmai release check
pmai release prepare --bump minor
pmai release publish
```

当前测试数字、已知限制和下一步只维护在 [`RUNTIME.md`](./RUNTIME.md)。

## 文档导航

- [`PRODUCT.md`](./PRODUCT.md)：产品定位、边界和成功标准
- [`RUNTIME.md`](./RUNTIME.md)：当前状态、验证基线和下一步
- [`CLAUDE.md`](./CLAUDE.md)：框架开发规则和文档同步约束
- [`AGENTS.md`](./AGENTS.md)：本仓入口规则
- [`CHANGELOG.md`](./CHANGELOG.md)：版本变更记录
- [`docs/INDEX.md`](./docs/INDEX.md)：设计、运行和归档文档索引

## 非交互骨架验证

```bash
tmp=$(mktemp -d)
bash scripts/init-project.sh Demo "$tmp/Demo" "一句话项目背景"
python3 scripts/status-view.py "$tmp/Demo" --narrative
```
