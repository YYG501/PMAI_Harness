# Windows 开发与验证

Windows 使用 PowerShell 入口和本机 Cygwin 运行时，执行同一套 Bash、Python 脚本与确定性测试，无需 WSL 或远程主机。当前验证状态只见 [`RUNTIME.md`](../../RUNTIME.md)。

## 支持范围

- 本地 NTFS、PowerShell 7.3 或更新版本、原生 Node.js，以及安装器准备的 Cygwin Bash / Python / Git。
- 框架 checkout 内脚本、隔离的安装与消费仓 fixture、护栏进程、原子文件写入和确定性回归。
- `run.ps1` 只设置子进程环境，结束后恢复 PATH 等变量；测试入口使用临时 Git 身份，不改用户 Git 配置。
- 原生 Windows CPython、网络盘、原生宿主 Skill 链接与 hook 配置、真实浏览器和模型会话不在本轮适配的已验证范围。原生宿主验收仍属于 H2，不能直接把 Cygwin 符号链接和 Bash hook 命令认作 Codex Desktop 可用入口。

## 准备运行时

先安装 PowerShell 7.3 或更新版本和 Node.js，确保当前 PowerShell 能找到 `node.exe`。从 [Cygwin 官方下载页](https://cygwin.com/install.html) 获取 `setup-x86_64.exe`，并从同一官方站点获取 `sha512.sum`，保存在同一目录。

在框架仓根运行：

```powershell
$downloadDir = Join-Path $env:USERPROFILE 'Downloads'
./scripts/windows/setup.ps1 `
  -Installer (Join-Path $downloadDir 'setup-x86_64.exe') `
  -ChecksumFile (Join-Path $downloadDir 'sha512.sum')
```

安装器先校验 SHA512，再以当前用户安装到 `$env:LOCALAPPDATA/PMAI/cygwin`，不要求管理员权限，不持久修改 PATH。Cygwin 官方安装器会维护自身安装记录与软件包缓存，需要联网下载依赖；它不会安装或升级全局 PMAI。

也可把运行时放到 checkout 的专用临时目录：

```powershell
$env:PMAI_WINDOWS_RUNTIME = Join-Path $PWD '.tmp/cygwin'
./scripts/windows/setup.ps1 `
  -Installer (Join-Path $downloadDir 'setup-x86_64.exe') `
  -ChecksumFile (Join-Path $downloadDir 'sha512.sum') `
  -RuntimeRoot $env:PMAI_WINDOWS_RUNTIME
```

运行时目录应独立于业务文件。重新执行 setup 可以补齐依赖；应等运行中的测试结束后再维护运行时。安装结束自动检测 Bash、Git、Python、Node、shasum、jq，以及文件锁和原子创建能力；安装器退出码为零本身不代表准备成功。

## 运行脚本和测试

```powershell
./scripts/windows/run.ps1 -Script scripts/repo-kind.py -Arguments @('--json')
./tests/run-windows.ps1 -Suite tests/test-atomic-file.sh

# 完整确定性回归，保留日志和退出码
./tests/run-windows.ps1 *> windows-tests.log
$testExitCode = $LASTEXITCODE
Get-Content windows-tests.log -Tail 30
```

相对 `-Script` 路径相对于框架根解析，工作目录保留调用位置。`-Arguments` 为字符串数组，通过 argv 传递，不拼进 shell 命令。PowerShell 文本管道按 UTF-8 传给子进程 stdin，支持 JSON、中文和空行。Bash/Python 脚本的目标路径参数使用 Cygwin 路径，可用运行时 `bin/cygpath.exe -u <Windows路径>` 转换。

测试入口先做能力预检。Cygwin 启动大量进程较慢，Windows 默认单套上限为 900 秒；可通过进程变量 `PMAI_SUITE_TIMEOUT_SECONDS` 覆盖，超时仍是失败。普通回归中未配置的模型会话显示 skip；发布门把必测会话缺失视为失败。

受限沙箱中若 Cygwin 无法访问当前用户目录，应通过宿主授权机制以当前用户执行；不要移除目录权限检查或关闭安全软件。

## 实现边界

- `.gitattributes` 固定文本 LF，避免 CRLF 改变 shell 与文本合同检查。
- `scripts/windows/node` 和 `hooks/host-process.cjs` 处理原生 Node 与 Cygwin 的路径边界；JSON stdin 保留原文，显式 Node preload 路径单独转换。
- `CHERE_INVOKING` 防止 Cygwin 登录 shell 从指定 worktree 跳回 HOME。
- Cygwin 目录 fd 会缓存旧路径。`scripts/_lib/cygwin_fs.py` 根据 Windows 句柄取得实际位置，持有临时禁止重命名的目录句柄并核对身份，再执行相对操作。虚拟盘符容器使用 Cygwin 稳定身份，真实目录仍执行完整检查。
- 文件创建使用 `renameat2(RENAME_NOREPLACE)`，已存在目标不能被覆盖。保留原有 symlink、父目录重绑、并发版本与恢复测试；威胁模型沿用 ADR-004。

Windows CI 使用相同安装器和测试入口。本地回归、CI、真实宿主和发布门的结果分别记录。
