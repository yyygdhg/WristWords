# WristWords

- Stage 1 — macOS CI environment
- Stage 2 — iOS + watchOS project skeleton
- Stage 3 — local vocabulary review MVP

```text
Windows
↓
GitHub
↓
GitHub Actions
↓
macOS + Xcode
```

- Windows 是主要代码编辑环境。
- GitHub Actions 提供临时 macOS/Xcode 编译环境。
- 使用 XcodeGen（至少 2.46.0），从 `project.yml` 生成 `WristWords.xcodeproj`。
- 两端编译同一份 `Shared` 源码和 5 个本地 Mock 单词，没有第三方 Swift Package 或签名配置。
- Watch 显示进度、单词、音标和中文释义；点击“忘记 / 模糊 / 认识”记录评价并前进，完成后显示 `Review Complete`，可 `Restart`。
- iPhone 展示相同 Mock 数据的数量与列表。
- `macos-environment.yml` 保留第一阶段的工具链验证；`app-build.yml` 从干净 checkout 生成工程、运行核心测试并实际编译两个 Simulator Debug Target。

Workflow 支持 `push`、`pull_request` 和手动触发 `workflow_dispatch`。
Swift 测试文件仅在 CI 临时目录生成，运行结束后清理。

## 工程结构

| Target / Scheme | 平台 | 最低系统版本 | Bundle Identifier |
| --- | --- | --- | --- |
| WristWords | iPhone / iOS | 17.0 | `com.example.WristWords` |
| WristWordsWatch | Apple Watch / watchOS | 10.0 | `com.example.WristWords.watchkitapp` |
| WristWordsCoreTests | macOS 核心逻辑测试 | 14.0 | `com.example.WristWords.coretests` |

```text
Shared/                    单词、MockVocabulary、StudySession 与三种评价
WristWords/App/            iPhone App 入口与单词列表
WristWordsWatch/App/       Watch App 入口与背词页面
Tests/                    StudySession 的 XCTest 测试
project.yml               三个 Target 的源码归属、设置与 Scheme
```

Session 是值类型，由 Watch 页面的 SwiftUI `@State` 保存。评价结果仅在该 Session 的内存中，Restart 清空结果；没有持久化、学习调度算法或两端同步。
测试 Target 直接编译相同的 Shared 源码，在 macOS Runner 上测试核心逻辑，无需为单元测试启动 iPhone 或 Watch 模拟器。

Watch 使用现代单 Target App 结构，设置 `WKApplication` 与 `WKCompanionAppBundleIdentifier`，作为 iPhone App 的 companion 嵌入 `PlugIns`，同时允许独立运行。
Bundle Identifier 是开发阶段占位值。最低系统版本是支持范围，不是要求安装相同版本的 SDK。

## 生成与编译（macOS）

Windows 编辑和提交源码；以下命令在安装了 Xcode 的 macOS 环境或 GitHub Actions Runner 执行。

```bash
# 如果尚未安装 XcodeGen
brew install xcodegen

# Generate project
xcodegen generate
xcodebuild -list -project WristWords.xcodeproj

# iPhone Simulator Debug build（也构建并嵌入 Watch App）
xcodebuild build -project WristWords.xcodeproj -scheme WristWords \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO

# 独立验证 Watch Simulator Debug build
xcodebuild build -project WristWords.xcodeproj -scheme WristWordsWatch \
  -configuration Debug \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath build/watchOS CODE_SIGNING_ALLOWED=NO

# 核心逻辑测试
xcodebuild test -project WristWords.xcodeproj -scheme WristWordsCoreTests \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build/tests CODE_SIGNING_ALLOWED=NO
```

工程和 Info.plist 由 `project.yml` 重新生成，不提交 `.xcodeproj`、`.generated` 或编译产物。
CI 删除首次生成的工程并重新生成，比较两次结果，运行核心测试，再构建并检查 App Bundle 与 companion 关系，最后确认 checkout 无未提交变化。
使用 Runner 默认 Xcode，每次输出实际 macOS、CPU、Xcode、Swift、XcodeGen 和 SDK 信息，未绑定特定 Xcode 安装路径。

8 个核心测试覆盖：初始单词、三种评价记录与前进、完整流程及评价顺序、完成后不再记录、完成后 Restart、途中 Restart、空 Session、不同 Session 状态独立。

当前自动验证范围为工程生成、核心逻辑测试和未签名 Simulator 编译；尚未进行 UI 点击自动化、真机运行、签名或发布验证。
