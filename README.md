# Shortcuts Bar ⚡

> 原生极简 macOS 菜单栏快捷指令启动器 · 复兴指哪打哪的桌面生产力  
> *A native, ultra-fast macOS menu bar launcher for Shortcuts with authentic icons, Liquid Glass determinate progress, and zero-latency execution.*

---

## 🌟 为什么需要 Shortcuts Bar？(Why Shortcuts Bar?)

macOS 近期版本将原本**「点击菜单栏图标 → 原地垂直下拉紧凑列表 → 单击即后台执行」**的原生经典交互，强制改版为类似 iPadOS 的控制中心大卡片组件（Controls API）。这一改动导致：

1. **桌面生产力与肌肉记忆被粉碎**：原本眼睛无需离开菜单栏、不足 1 秒即可盲操执行的脚本，被强行改版为遮挡屏幕、点击目标分散的浮动大卡片。
2. **管理排版倒退**：常用脚本无法整齐紧凑罗列，多脚本查找繁琐。
3. **执行状态模糊**：过去极具仪式感的环形进度（ScriptMonitor 原生指示器）被削弱，执行状态难以感知。

**Shortcuts Bar 为彻底解决这些痛点而生**——采用纯 Swift 6 与 AppKit 原生重构，100% 还原并大幅升级极简、高效、利落的桌面级下拉交互！

---

## ✨ 核心特性 (Key Features)

### 1. ⚡ 秒级原生下拉与静默执行
- 点击菜单栏图标，原生 `NSMenu` 瞬时滑出（响应时延 < 50ms）。
- 鼠标滑选单击即在后台异步唤起 `/usr/bin/shortcuts run`，耗时不足 1 秒，完全保留桌面级高精度操作习惯。

### 2. 🎨 真实快捷指令原生图标渲染
- 拒绝粗糙的统一 `⌘` 占位符号。
- 底层通过 `SQLITE_OPEN_READONLY` 只读解析 `~/Library/Shortcuts/Shortcuts.sqlite`，获取每个指令真实的 `ZGLYPHNUMBER` 与 `ZBACKGROUNDCOLORVALUE`。
- 动态调用系统级渲染通道，高精呈现原生 RGBA 渐变圆角矩形与对应 SF Symbols 符号，自带内存多级 `NSCache` 缓存。

### 3. ⏱️ 严格遵循 Apple HIG 的确定性进度指示圈
- **Apple HIG 规范设计**（参考 [Apple Human Interface Guidelines: Progress Indicators](https://developer.apple.com/cn/design/human-interface-guidelines/progress-indicators)）。
- **macOS 26+ 液态玻璃（Liquid Glass）视觉系统**：
  - **进度 0% 对应“浅底圈”**：任务启动瞬间，呈现细腻磨砂底槽（深色模式为 `white(0.18)` 玻璃微光，浅色模式为 `black(0.14)` 柔和透光，1.5pt 线宽）。
  - **顺时针填充**：从 12 点钟方向（正上方）顺时针平滑生长，颜色严格遵循系统原生强调色（`NSColor.controlAccentColor`）。
  - **100% 满圈反馈**：执行完结瞬间填满整圈 360°，给予明确的成功信号后平滑淡出。

### 4. 🔄 零重启实时无感热同步
- 内核级 `DispatchSourceFileSystemObject` 主动监听 `~/Library/Shortcuts/` 目录。
- 当在系统快捷指令 App 内新增、重命名、编辑或删除指令时，系统通过 350ms 防抖静默热刷新缓存，展开菜单永远最新，**彻底告别手动重启 App**。

### 5. 🛑 智能任务队列与单键终止
- **自适应阈值分流**：
  - 正在运行的任务 $\le 3$ 个：直接在菜单顶部内联罗列，显示实时运行秒表（`00:03`）与总步数（如 `18 步`）；
  - 正在运行的任务 $> 3$ 个：自动收纳折叠为「正在运行的任务 (N) ▶」二级子菜单，附带「一键终止所有」功能，绝不撑爆屏幕。
- **纯净 SF Symbol 停止键**：移除冗余冗长文字，仅保留纯净、精致的 `stop.circle.fill`，一键优雅发送 `SIGTERM` 终止进程。

### 6. ⚙️ 灵活的作用域管理
- **单文件夹直出模式**：默认绑定快捷指令的「菜单栏 (Menu Bar)」专用文件夹，启动菜单纯扁平秒点。
- **全库层级模式**：支持切换至全库根目录，以清晰的二级子菜单树罗列所有文件夹与未分类指令。
- **开机自启与失败通知**：偏好设置集成 `SMAppService` 登录自启与系统失败弹窗通知。

### 7. 🛡️ 严格非破坏性安全契约
- 仅作为只读与调度客户端，绝不直接写入或修改系统 SQLite。
- 绝不改动、污染或删除用户的任何现有快捷指令。

---

## 🏗️ 架构与技术栈 (Architecture)

- **语言版本**：Swift 6（开启并发安全检查）
- **界面框架**：AppKit（`NSStatusItem`, `NSMenu`）+ SwiftUI（`SettingsView`）
- **依赖关系**：**零第三方外部依赖 (Zero External Dependencies)**，纯原生 macOS SDK 实现。
- **运行模式**：桌面辅助代理 (`LSUIElement = 1`)，常驻状态栏，无 Dock 栏图标打扰，内存占用 < 20MB。

```
ShortcutsBar/
├── Package.swift
├── Sources/
│   ├── ShortcutsBar/               # 应用入口与生命周期管理 (AppDelegate)
│   └── ShortcutsBarCore/
│       ├── Models/                 # 数据模型 (ShortcutItem, RunningTask, FolderScope)
│       ├── Services/               # 核心后台服务
│       │   ├── ShortcutsService.swift         # CLI 调度与目录拉取
│       │   ├── ShortcutsMetadataReader.swift  # SQLite 只读元数据解析
│       │   ├── ShortcutsDatabaseWatcher.swift # 文件系统变化内核级监听
│       │   ├── ProcessManager.swift           # 进程池管理与 SIGTERM 取消
│       │   └── PreferencesStore.swift         # 偏好配置持久化
│       ├── UI/                     # 原生 AppKit 与 SwiftUI 界面
│       │   ├── MenuBuilder.swift              # 动态原生 NSMenu 构建器
│       │   ├── RunningTaskView.swift          # 运行任务行与实时秒表
│       │   ├── SettingsView.swift             # 偏好设置视图
│       │   └── StatusItemController.swift     # 状态栏控制器
│       └── Utilities/              # 图标生成与渲染引擎
│           ├── ShortcutIconRenderer.swift     # 快捷指令图标提取渲染器
│           ├── ShortcutsIconFactory.swift     # 双菱形原生几何生成器
│           └── ScriptMonitorSpinnerView.swift # Liquid Glass 环形进度指示器
├── Tests/ShortcutsBarTests/        # 单元测试与非破坏性安全集成测试
└── scripts/
    ├── generate_app_icon.swift     # 高清 AppIcon.icns 多尺寸生成脚本
    └── package_app.sh              # 一键编译与签名独立应用脚本
```

---

## 🚀 构建与运行 (Build & Run)

### 系统要求
- macOS 14.0 (Sonoma) 或 macOS 15.0+ (Sequoia)
- Xcode 15.0+ / Swift 6.0+
- Apple Silicon (M1/M2/M3/M4) 或 Intel 架构均可支持

### 编译与打包独立应用
在项目根目录下一键执行：

```bash
chmod +x scripts/package_app.sh
./scripts/package_app.sh
```

脚本将自动完成：
1. Swift 6 Release 生产优化编译
2. 组装标准 macOS 应用目录结构（`ShortcutsBar.app`）
3. 动态绘制 16px 至 1024px 全分辨率 `AppIcon.icns`
4. 注入 `LSUIElement` 并自动完成本地 Codesign 签名

生成产物位于项目根目录：**`ShortcutsBar.app`**。直接将其拖入 `/Applications` 文件夹即可使用。

---

## 🧪 自动化测试 (Testing)

项目配备了严格的单元测试与安全集成测试套件，全面覆盖解析器、状态机、多进程取消、UI 构造与文件系统监听：

```bash
swift test
```

> **安全验证保障**：内置 `SafeIntegrationTests`，测试运行前后自动对比系统指令数量与哈希指纹，确保在任何测试环境下均不产生数据污染。

---

## 📄 开源许可证 (License)

本项目基于 [MIT License](LICENSE) 开源。
