# 合盖运行

让 MacBook 合上盖子后继续运行（跑 agent、跑长任务），到时自动恢复正常休眠。
2026-09-01 由 Claude Code 从三处散落位置搜集建立，**原件全部保留在原位**。

## 背景

`caffeinate` 只能阻止**空闲休眠**，压不住**合盖休眠**。合盖运行依赖 macOS 隐藏设置
`pmset disablesleep`。这是非公开、不受支持的机制，可能随 macOS 版本变化，
且会带来电池与散热风险。所以两个脚本都做了硬性护栏。

> **紧急恢复**：`sudo pmset -a disablesleep 0`

## 目录

```
scripts/
  合盖持续运行.command          电源版：1–24 小时，要求接 AC
  合盖持续运行_电池临时.command  电池版：1–4 小时，要求用电池，电量 ≤10% 自动停
gui/
  合盖运行控制.applescript      双击弹窗控制（开启 / 关闭），AppleScript 版
  合盖运行控制.js               同上，JXA 版（.app 内嵌的是这一份）
app/
  合盖运行控制.app              已构建的双击启动器
```

## 两个脚本的护栏

共同点：启动前先检查是否已开启（已开启则提供恢复选项）；时长参数校验；
`sudo -v` 单独取管理员授权；开启后**验证** `SleepDisabled 1` 确实生效，验证不过就退出；
每 30 秒轮询一次电源状态；`trap ... EXIT` 保证到时、断电、Ctrl+C、终止、异常退出
**都会**执行 `pmset disablesleep 0`；内置 `--self-test` 模式做参数校验自检。

| | 电源版 | 电池临时版 |
|---|---|---|
| 前置条件 | 必须 AC Power | 必须 Battery Power |
| 时长 | 1–24 小时（默认 4） | 1–4 小时（默认 1） |
| 作用域 | `pmset -a`（全局） | `pmset -b`（仅电池） |
| 额外保护 | 断电即恢复 | 断电即恢复 + 电量 ≤10% 即恢复 |

## 出处

| 本仓库路径 | 原始位置 |
|---|---|
| `scripts/*.command` | `~/Documents/ChatGPT/多agent工作/` |
| `gui/合盖运行控制.applescript`、`gui/合盖运行控制.js` | `~/Documents/Codex/2026-08-31/xiay/outputs/` |
| `app/合盖运行控制.app` | `~/Desktop/合盖运行控制.app` |

未收录：`xiay/a.scpt`（编译后的 AppleScript 存根，只是激活 Finder，与本项目无关）。

## ⚠️ 路径耦合

`app/合盖运行控制.app` 内嵌的脚本把启动器路径**硬编码**为：

```
/Users/ben/Documents/ChatGPT/多agent工作/合盖持续运行_电池临时.command
```

两个 GUI 源码里也是同一个硬编码路径。因为搜集是**复制**而非移动，
桌面上的 `.app` 现在照常可用。但如果以后删掉或移动 `~/Documents/ChatGPT/多agent工作/`，
`.app` 就会失效。届时需要把路径改成 `~/Documents/合盖运行/scripts/合盖持续运行_电池临时.command`
并重新构建 `.app`。

## 验证状态

- 已验证：`zsh -n` 语法检查通过、`--self-test` 参数自检输出「自检通过」、
  可执行位 `-rwxr-xr-x`、当前 `SleepDisabled 0`（未残留系统改动）
- **未验证**：没有做过真实的合盖硬件端到端测试（需要实际改动电源设置）

## 安全提醒

开启期间机器必须放在**通风的硬质桌面**上。不要放进包里、床上或沙发上——
合盖且不休眠意味着持续发热而机身散热受阻。
