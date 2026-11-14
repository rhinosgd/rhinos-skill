---
name: 双Workbuddy账号登录
description: 在同一台 Windows 或 macOS 设备上同时登录两个 WorkBuddy 账号（A/B），并各自沿用本机的对话历史记录。适用于需要双账号并行、且不希望任一账号在新窗口显示为"新设备"空白历史的场景。当用户说"双开 WorkBuddy""两个账号同时登录""同一台电脑登两个 WB 账号""双 WorkBuddy 账号"时调用。
---

# 双 WorkBuddy 账号登录

在一台设备上同时跑两个 WorkBuddy 窗口：窗口 1 = 当前账号（A，含完整体机历史），窗口 2 = 另一个账号（B，沿用 B 的本机历史）。两个窗口登录态互不干扰。

## 为什么必须这么做（核心原理）

WorkBuddy 有两条"按操作系统用户隔离"的硬约束（已从安装包 `app.asar` 源码确认）：

1. **登录态（auth token）按 Windows/macOS 用户主目录隔离**，不随 `WORKBUDDY_CONFIG_DIR` 改变。同一系统用户开两个实例，会被文件监视器强制同步成同一个账号。
2. **单实例锁按配置目录（数据目录）加锁**。同目录第二个进程直接退出。

因此"同用户双开"必然同账号。要两个不同账号并行，**必须给第二个窗口一个独立的系统用户环境**（独立的主目录 / HOME），再把历史库克隆过去。

详见 `references/mechanism.md`。

## 支持的平台与做法

| 平台 | 第二窗口隔离方式 | 是否需要管理员 | 可靠性 |
|------|----------------|---------------|--------|
| Windows | 新建第二个本地 Windows 用户（如 `WBUser2`），`runas` 启动 | 是（建用户/写其他用户目录） | 已验证 ✅ |
| macOS | 为第二实例指定独立的 `HOME` 目录（历史克隆进去） | 否 | 实验性 ⚠️，附第二用户兜底 |

## 使用方法（给安装此 Skill 的设备）

调用本 Skill 后，按以下步骤自动执行：

### Windows
1. 以**管理员**身份运行本 Skill 提供的 `scripts/setup_windows.ps1`：
   ```powershell
   powershell -ExecutionPolicy Bypass -File "<skill>/scripts/setup_windows.ps1" [-SecondUser WBUser2] [-Password 你的密码]
   ```
2. 脚本会：创建/校验第二个本地用户 → 把当前用户的 WorkBuddy 本机历史（对话记录）定向克隆到该用户配置目录 → 生成桌面快捷方式 **`WorkBuddy 2Accounts.lnk`**。
3. 双击桌面 **`WorkBuddy 2Accounts`**：窗口 1 自动以当前账号 A 打开（历史完整）；窗口 2 以第二用户打开并自动/手动登录账号 B，显示 B 的本机历史。
4. 首次运行窗口 2 会提示输入第二用户的密码（之后 `/savecred` 记住，不再提示）。

### macOS
1. 普通权限运行 `scripts/setup_mac.sh`：
   ```bash
   bash "<skill>/scripts/setup_mac.sh" [ALT_HOME] [WORKBUDDY_APP]
   ```
2. 脚本会：创建独立 `HOME`（默认 `~/WorkBuddyAltHome`）→ 把当前 `.workbuddy` 历史定向克隆进去 → 在桌面生成 **`WorkBuddy 2Accounts.command`**。
3. 双击该 `.command`：窗口 1 = 主账号 A；窗口 2 = 独立 HOME 下的实例，登录账号 B 即可看到 B 的历史。
4. 若第二窗口被"单实例锁"拦截无法启动，改用 Skill 说明里的**第二 macOS 用户兜底方案**（建立方用户 + 快速用户切换，或 `sudo -u` 启动）。

## 重要说明与限制

- **克隆的是"对话历史"**，不是工程文件。`workspaces` 表里的工程路径绑定的是原用户目录，第二窗口能看历史对话文本，但点击"打开工程"可能因路径/权限打不开（工程文件需另行处理）。
- 克隆时**排除了可再生/重量级目录**（`workspace`、`binaries`、`app`、`logs`、`plugins`、`projects`、`traces`、`cache` 等），只搬 `workbuddy.db` + 附件(`blobs`/`storage`/`local_storage`) + 个人目录 + 配置，体积约 100–200MB，避免几 GB 的无效复制。
- 第二窗口登录的是**另一个账号**，需要你用该账号扫码/授权登录一次（登录态无法跨用户复制，也不应复制）。
- 第二窗口看到的"本机历史"= 你之前在该账号下、于本机产生过的对话；如果你从未在本机用 B 登录过，自然没有 B 的历史。

## 给 Agent 的执行指引

收到"双开 / 两个账号 / 双 WorkBuddy 账号"类请求时：

1. 用 `uname` / `$env:OS` 判断平台。
2. **Windows**：先确认以管理员运行；运行 `setup_windows.ps1`（可传参），完成后核对桌面快捷方式存在、目标 `workbuddy.db` 与源字节一致、第二用户已建。
3. **macOS**：运行 `setup_mac.sh`；提示用户这是实验性方案，若单实例锁拦截则引导第二用户兜底。
4. 向用户清晰说明：窗口 1=A（自动）、窗口 2=B（需登录一次）、历史沿用、工程文件限制。
