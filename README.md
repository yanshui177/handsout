# Handsout

<p align="center">
  <img src="docs/icon.png" width="128" alt="Handsout 图标">
</p>

给常用 app 绑上 `⌥+字母/数字`，按住 `⌥` 看一眼全部快捷键，再按一次把应用收回去。

一个 macOS 菜单栏常驻的快捷键启动器：原生 Swift + SwiftUI，无第三方依赖，不依赖 Xcode 工程，一条命令就能构建出 `.app`。

## 特性

- **菜单栏常驻**：不显示 Dock 图标，不进 Cmd+Tab
- **给应用绑快捷键**：`⌥+字母/数字` 一键唤起；已运行则切到已有实例
- **长按 ⌥ 看面板**：按住 `⌥` 超过阈值（默认 0.35s，可调）弹出 HUD，显示图标、名称、快捷键角标；继续按键或直接点击都能启动，松手自动关闭
- **再按一次收回**：同一个键按第二次时（目标已在前台），隐藏它并自动切回上一个应用；再按一次又能唤回来。设置里可关掉
- **关掉窗口也能打开**：Finder 这类应用关掉全部窗口后进程仍在，会先探测目标是否真有窗口，没有就走真正的打开流程（Finder 开一个访达窗口，其它应用触发 reopen）
- **自动分配快捷键**：添加时按应用名首字母分配 `⌥+X`，被占用则顺延
- **快捷键录制**：点一下输入框按下新组合即可；必须带修饰键（防误触）；冲突自动接管并提示
- **开机启动**：登录项开关（建议先把 app 放到 `/Applications` 再开启）
- 配置存本地 JSON，无网络请求、无遥测

## 安装

### 方式一：下载预编译版

从 Releases 下载 `Handsout.app.zip`，解压后把 `Handsout.app` 拖到 `/Applications`，双击运行即可。

> 未签名的 app 首次打开可能被 Gatekeeper 拦一下：右键 →「打开」，或在「系统设置 → 隐私与安全性」里点「仍要打开」。

### 方式二：从源码构建

要求：macOS 13+ 与 Xcode Command Line Tools（内含 Swift 6）。

```bash
git clone <你的仓库地址> Handsout
cd Handsout
./build.sh                    # 编译 release + 生成图标 + 组装 dist/Handsout.app + ad-hoc 签名
open dist/Handsout.app
cp -r dist/Handsout.app /Applications    # 可选：装到应用程序目录
```

调试时直接跑二进制更方便（`open --args` 对菜单栏应用传参不稳定）：

```bash
./dist/Handsout.app/Contents/MacOS/Handsout --settings   # 直接打开设置窗口
./dist/Handsout.app/Contents/MacOS/Handsout --hud        # 直接弹出快捷键面板
```

### 发版（维护者）

需要 GitHub Personal Access Token（`repo` 权限），存进钥匙串更保险：

```bash
./Scripts/release.sh set-token     # 首次：token 存进 macOS 钥匙串（不回显、不进命令行历史）
./Scripts/release.sh v1.0.0        # 构建 -> 打包 -> 建 Release -> 上传 zip 附件
```

Release 说明写在 `docs/release-notes.md`，发版时会自动作为 Release body 上传。

## 使用

1. **启动与授权**：首次运行会在菜单栏出现双手图标，并自动弹出设置窗口。到窗口底部点「请求权限」，在系统设置里勾选 Handsout（辅助功能）。**没有这个权限，长按 ⌥ 弹面板不生效**，`⌥+字母` 直接启动仍然可用。
2. **添加应用**：设置窗口右上角「添加应用」选择 `.app`，或「从已安装应用添加」在扫描列表里搜索添加。
3. **改快捷键**：点列表里的快捷键输入框，按下新组合（如 `⌘⇧F`），`Esc` 取消。与已有快捷键冲突时会接管对方的键位并提示。
4. **长按 ⌥**：按住 `⌥` 0.35 秒弹出面板，面板上点击图标即可启动，松开 `⌥` 关闭。
5. **再按一次收回**：应用已经在前台时，再按同一个键会把它隐藏并回到你上一个在用的应用。

设置窗口里的开关：

| 设置项 | 说明 |
| --- | --- |
| 长按 ⌥ 触发延迟 | 0 ~ 1.2 秒，0 表示按下立即弹出 |
| 再按一次隐藏 | 关闭后，重复按同一个键只会再次激活应用 |
| 开机启动 | 走系统登录项，建议 app 放在 `/Applications` 后再开 |
| 辅助功能权限 | 实时状态灯 + 授权入口 |

配置文件：`~/Library/Application Support/Handsout/config.json`（可直接编辑或删除重置）。

## 权限

| 能力 | 是否需要辅助功能权限 |
| --- | --- |
| `⌥+字母` 全局热键启动 | 不需要（Carbon `RegisterEventHotKey`） |
| 长按 `⌥` 弹面板 | **需要**（要监听全局按键事件） |

应用只在本机读取应用列表、启动应用，不联网、不上传任何数据。

## 项目结构

```
Package.swift                 SwiftPM 清单（Swift 5 语言模式）
Resources/Info.plist          LSUIElement=1，菜单栏应用的关键
Sources/Handsout/
  HandsoutApp.swift           @main + 菜单栏菜单
  AppDelegate.swift           生命周期、热键重绑、设置窗口
  Models.swift                LaunchItem / 配置持久化 / 启动与切换 / 应用扫描 / 权限
  HotKeyCenter.swift          Carbon 全局热键注册
  KeyCodes.swift              虚拟键码 <-> 显示名、修饰键换算
  OptionMonitor.swift         长按 ⌥ 检测（全局 + 本地 flagsChanged）
  WindowProbe.swift           判断应用是否真有可见窗口
  AppTracker.swift            记录"上一个活跃应用"，用于切回去
  HUD.swift                   快捷键面板（NSPanel + NSVisualEffectView + SwiftUI）
  SettingsView.swift          设置界面 + 快捷键录制控件
Scripts/make_icon.py          纯标准库绘制图标并生成 icns
```

## 实现笔记

几个踩过坑、值得留档的点：

- **热键走 Carbon**：`RegisterEventHotKey` 不需要辅助功能权限，比 CGEventTap 更省电、更稳。
- **长按检测走 `NSEvent` 全局监听**：需要辅助功能权限；必须同时加 `addLocalMonitorForEvents`，否则本应用窗口在前台时收不到。
- **判断"有没有窗口"要用 `CGWindowList`**：常驻进程（Finder）关掉全部窗口后仍在运行，`activate` 它是没反应的。别用 AX 的 `kAXWindowsAttribute` —— 它会把 Finder 的桌面当成窗口，永远返回 true。
- **`hide()` / `activate()` 都是异步生效**的（焦点切换实测可能要 1 秒）：隐藏后切回上一个应用要延迟约 0.35s，唤起失败还要延迟 1s 兜底补一次。
- **菜单栏应用激活别人前要先激活自己**：`NSApp.activate(ignoringOtherApps: true)`，否则系统常常无视 activate 请求。
- **HUD 不抢焦点**：`.nonactivatingPanel` + `canBecomeKey = false`，避免打断当前输入。

## 已知限制

- 长按 ⌥ 依赖辅助功能权限，未授权时只能用「⌥+字母直接启动」和菜单里的「显示快捷键面板」。
- 面板最多 6 列，超出换行显示。
- 开机启动失败（app 不在 `/Applications`、签名异常等）时，设置界面会显示具体错误。

## 许可证

[MIT](LICENSE)

---

Handsout 是独立开发的开源小工具，代码与图标资源均为原创，不含任何第三方商业软件的代码或资源。
