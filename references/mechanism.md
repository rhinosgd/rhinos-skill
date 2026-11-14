# 双 WorkBuddy 账号登录 — 原理与排错

## 一、为什么"同用户双开"必然同账号

从 WorkBuddy 安装包 `resources/app.asar` 逆向确认：

1. **单实例锁**：Electron 的 `app.requestSingleInstanceLock()` 按**配置目录（数据目录）**加锁。同一配置目录启动第二个进程会直接 `app.quit()` 退出。
2. **登录态按操作系统用户主目录隔离**：
   - Windows：`%USERPROFILE%\.workbuddy`（配置/历史库 `workbuddy.db`）+ `%LOCALAPPDATA%\CodeBuddyExtension\Data\Public\auth\workbuddy-desktop.info`（登录 token）。两者都绑定 Windows 用户主目录。
   - macOS：`~/.workbuddy` + `~/Library/Application Support/...`。
   - 这是一个**加密 token**（`$wbEncrypted:1`，机器级密钥），按"用户主目录"落地，不随 `WORKBUDDY_CONFIG_DIR` 环境变量改变。
3. **文件监视器实时同步**：同一 Windows 用户开多个实例时，登录态文件被监视并强制同步 → 所有同用户窗口必然是同一账号。

结论：**要让两个窗口登录不同账号，必须给第二个窗口一个独立的"系统用户环境"**（独立主目录 / HOME）。仅改 `WORKBUDDY_CONFIG_DIR` 不行——它只隔离项目/设置，不隔离登录态。

## 二、方案设计

| 平台 | 隔离手段 | 登录态 | 历史库 | 是否需要管理员 |
|------|---------|--------|--------|---------------|
| Windows | 第二个本地 Windows 用户 + `runas` | 独立（WBUser2 自己的 token） | 克隆到 `C:\Users\WBUser2\.workbuddy` | 是（建用户 / 写他人目录） |
| macOS | 第二实例指定独立 `HOME` | 独立（`$ALT_HOME` 下） | 克隆到 `$ALT_HOME/.workbuddy` | 否 |

### 历史库结构（关键）
- 对话历史主要在 **`workbuddy.db`**（SQLite，`sessions` 表按 `user_id` 区分账号）。
- 附件/产物在 `blobs`、`storage`、`local_storage`。
- 个人目录：`user-<user_id>-personal`、`<user_id>`。
- `workspaces` 表把工程绑定到**原用户绝对路径**（如 `C:\Users\Administrator\WorkBuddy\...`），第二窗口打不开这些工程文件（路径不匹配 + 权限不足）——但历史**对话文本**不受影响。

### 克隆时要排除的目录（可再生/重量级，不必搬）
`workspace`、`binaries`、`app`、`logs`、`plugins`、`projects`、`traces`、
`connectors-marketplace-sources`、`cache`、`Crashpad`、`node_modules`、
`external-packages`、`native-runtimes`。
排除后复制量从数 GB 降到约 100–200MB，且稳定可一次完成。

## 三、Windows 实施要点（已验证）
- 用 `net user` 建第二用户（`/add`、`/expires:never`、`/active:yes`）。
- `robocopy /MIR /XD <排除列表> /COPY:DAT` 做定向镜像；`/COPY:DAT`（不带 `/SEC`）使新文件**继承目标目录 ACL**，第二用户自动有完全控制权，无需额外 `icacls`。
- 第二用户**登录态需自己登一次**（token 不能跨用户复制，也不该复制）。登的是哪个账号，就显示哪个账号的本机历史。
- 启动器：窗口1 `Start-Process WorkBuddy.exe`（当前用户=A）；窗口2 `runas /savecred /profile /user:机器名\WBUser2`。首次提示密码，之后记住。
- 桌面快捷方式用 `WScript.Shell` 创建，指向启动器 `.ps1`。

## 四、macOS 实施要点与兜底

### 4.1 主法（已验证）：包装 .app + `open -a`
- **关键坑**：WorkBuddy 的 Electron 二进制**不能直接从 shell `exec`**。直接运行 `/Applications/WorkBuddy.app/Contents/MacOS/Electron`（无论是否带 `HOME=$ALT_HOME`）都会报：
  `Node.js environment variables are disabled because this process is invoked by other apps.`
  然后直接退出。原因是该二进制必须经 LaunchServices（`open -a`）以合法上下文启动。
- 但 `open -a` **不继承 shell 的 `HOME` 环境变量**，所以光用 `open -a /Applications/WorkBuddy.app` 无法隔离登录态（还是会读真实 HOME）。
- **解法**：建一个极简**包装 .app**，其可执行脚本先 `export HOME=$ALT_HOME` 再 `exec` 真正的 Electron 二进制；用 `open -a` 启动这个包装 app，既拿到合法启动上下文绕开报错，又把 HOME 隔离到位。实测可同时跑起两个完全独立的 WorkBuddy 实例（第二实例的 `--user-data-dir` 指向 `$ALT_HOME/.workbuddy/app`，登录态/历史隔离）。
- 单实例锁按 `userData`（即 `$HOME/.workbuddy/app`）加锁，两个实例 HOME 不同 → userData 不同 → 锁互不冲突，第二窗口正常启动。

### 4.2 兜底（仍可靠）：第二 macOS 用户
- 若你的 WorkBuddy 版本单实例锁是**全局**（按 app bundle id），包装 .app 方案可能失效，此时改用：建第二个 macOS 用户 → 快速用户切换登录该用户 → 在其会话里跑 WorkBuddy 登 B。两个用户会话同时登录，用 Mission Control / 空间并排查看。

## 五、常见故障
- **窗口2 登成了 A**：第二环境里残留了 A 的 token。清空该环境的 auth 目录后重登 B。
- **历史空白**：`workbuddy.db` 没克隆成功。核对源/目标字节一致；确认排除列表没把 `workbuddy.db` 误排。
- **第二窗口起不来（macOS）**：若报 `Node.js environment variables are disabled...`，说明脚本没走 `open -a` 包装方案——请重跑 `setup_mac.sh` 确保生成了 `~/WorkBuddyAlt.app` 并用它启动；若仍失败，改用第二 macOS 用户兜底。
- **点开工程报错**：预期内（`workspaces` 路径绑定原用户），非故障，对话历史本身可用。
