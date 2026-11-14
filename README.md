# 双 WorkBuddy 账号登录（Dual WorkBuddy Account Login）

> 在同一台 **Windows 或 macOS** 设备上，**同时登录两个 WorkBuddy 账号（A/B）**，并且 **A/B 各自沿用本机的对话历史记录**——不会像换设备登录那样变成"新设备空白历史"。

这是一个 WorkBuddy **Skill（技能）**。把它放进 WorkBuddy 的技能目录即可使用，适合需要在同一台电脑上并行使用工作号 / 个人号、且希望两边历史都不丢失的用户。

---

## 一句话原理

WorkBuddy 的 **登录态（token）是按操作系统用户主目录隔离的**，而且 **单实例锁按配置目录加锁**。所以"同一个系统用户开两个窗口"必然被强制同步成同一个账号——**同用户双开 = 同账号，无解**。

要让两个窗口登录**不同**账号，必须给第二个窗口一个**独立的系统用户环境**（独立的主目录 / HOME），再把历史库克隆过去。本 Skill 自动完成这件事。

详见 [`references/mechanism.md`](references/mechanism.md)。

---

## 平台支持

| 平台 | 第二个窗口的隔离方式 | 是否需要管理员 | 可靠性 |
|------|-------------------|---------------|--------|
| **Windows** | 新建第二个本地 Windows 用户（如 `WBUser2`），用 `runas` 拉起 | 是（建用户 / 写其他用户目录） | ✅ 已验证 |
| **macOS** | 为第二个实例指定独立的 `HOME` 目录 | 否 | ⚠️ 实验性，附第二用户兜底方案 |

---

## 安装 Skill（发给别人 / 换设备）

1. 下载本仓库（Zip 或 `git clone`）。
2. 把整个 `双Workbuddy账号登录/` 目录（或解压后的目录）放到 WorkBuddy 的**用户级技能目录**：
   - Windows：`C:\Users\<你的用户名>\.workbuddy\skills\双Workbuddy账号登录\`
   - macOS / Linux：`~/.workbuddy/skills/双Workbuddy账号登录/`
3. 重启或刷新 WorkBuddy，对 WorkBuddy 说"**双开 WorkBuddy / 两个账号同时登录**"，即可触发本技能自动执行。

> 也可以把目录改名成英文（如 `dual-workbuddy-login`）以避免路径中文兼容问题，技能名以 `SKILL.md` 里的 `name:` 为准。

---

## 使用方法

### Windows

以**管理员**身份运行安装脚本（第二用户默认 `WBUser2`，密码默认 `WorkBuddy@2026`，可用参数覆盖）：

```powershell
powershell -ExecutionPolicy Bypass -File "<skill>/scripts/setup_windows.ps1" `
  [-SecondUser WBUser2] [-Password 你的密码]
```

脚本会依次：
1. 创建 / 校验第二个本地 Windows 用户；
2. 把**当前用户**的 WorkBuddy 本机历史（对话记录）定向克隆到该用户配置目录（排除数 GB 的可再生目录，只搬 `workbuddy.db` + 附件 + 个人目录 + 配置，约 100–200MB）；
3. 在桌面生成快捷方式 **`WorkBuddy 2Accounts.lnk`**。

之后**双击桌面 `WorkBuddy 2Accounts`**：
- **窗口 1** = 当前账号 A（历史完整）；
- **窗口 2** = 以第二 Windows 用户打开，用你的**第二个账号 B** 扫码 / 授权登录一次（之后记住，不再提示），登录后显示 B 的本机历史。

### macOS

普通权限运行：

```bash
bash "<skill>/scripts/setup_mac.sh" [ALT_HOME] [WORKBUDDY_APP]
```

默认 `ALT_HOME=~/WorkBuddyAltHome`，`WORKBUDDY_APP=/Applications/WorkBuddy.app`。脚本会：
1. 创建独立 `HOME` 并把当前 `.workbuddy` 历史定向克隆进去；
2. 在桌面生成 **`WorkBuddy 2Accounts.command`**。

双击该 `.command`：窗口 1 = 主账号 A；窗口 2 = 独立 HOME 下的实例，登录账号 B 即可看到 B 的历史。

> ⚠️ macOS 方案依赖"独立 HOME 能绕开单实例锁"。若第二窗口被单实例锁拦截无法启动，请改用**第二 macOS 用户兜底**：新建一个 macOS 用户 → 快速用户切换登录该用户 → 在其会话里跑 WorkBuddy 登 B；两个用户会话同时保持登录，用 Mission Control / 空间并排查看。

---

## 重要说明与限制

- **克隆的是"对话历史"，不是工程文件**。`workspaces` 表里的工程路径绑定的是原用户目录，第二窗口能看到历史对话文本，但点击"打开工程"可能因路径 / 权限打不开（工程文件需另行处理）。
- **第二个账号需要你登录一次**：登录态（token）不能、也不应该跨用户复制，所以窗口 2 首次需扫码 / 授权登录 B。
- 第二窗口看到的"本机历史"= 你之前在该账号下、**于本机**产生过的对话；如果你从未在本机用 B 登录过，自然没有 B 的历史。
- 克隆时已排除可再生 / 重量级目录（`workspace`、`binaries`、`app`、`logs`、`plugins`、`projects`、`traces`、`cache` 等），避免几 GB 的无效复制。

---

## 仓库结构

```
双Workbuddy账号登录/
├── SKILL.md                 # 技能定义、原理、双平台用法、Agent 执行指引
├── README.md                # 本使用说明
├── references/
│   └── mechanism.md         # 从安装包逆向确认的原理与排错手册
└── scripts/
    ├── setup_windows.ps1    # Windows 安装脚本（建第二用户 + 克隆历史 + 桌面快捷方式）
    └── setup_mac.sh         # macOS 安装脚本（独立 HOME + 克隆历史 + 桌面启动器）
```

---

## 工作原理细节

- 对话历史主要在 `workbuddy.db`（SQLite，`sessions` 表按 `user_id` 区分账号）；附件 / 产物在 `blobs`、`storage`、`local_storage`。
- Windows：`%USERPROFILE%\.workbuddy` + `%LOCALAPPDATA%\CodeBuddyExtension\Data\Public\auth\workbuddy-desktop.info`（登录 token，机器级加密，按用户主目录落地）。
- 克隆用 `robocopy /MIR /XD <排除列表> /COPY:DAT`（Windows）/ `rsync --exclude`（macOS），`/COPY:DAT` 让新文件继承目标目录 ACL，第二用户自动拥有完全控制权。

更完整的原理、实施要点与故障排查见 [`references/mechanism.md`](references/mechanism.md)。
