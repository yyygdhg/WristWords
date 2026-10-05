# WristWords

- Stage 1 — macOS CI environment
- Stage 2 — iOS + watchOS project skeleton

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
- 两个 SwiftUI App 只展示项目名称和平台文字，没有业务功能、第三方 Swift Package 或签名配置。
- `macos-environment.yml` 保留第一阶段的工具链验证；`app-build.yml` 从干净 checkout 生成工程并实际编译两个 Simulator Debug Target。

Workflow 支持 `push`、`pull_request` 和手动触发 `workflow_dispatch`。
Swift 测试文件仅在 CI 临时目录生成，运行结束后清理。

## 工程结构

| Target / Scheme | 平台 | 最低系统版本 | Bundle Identifier |
| --- | --- | --- | --- |
| WristWords | iPhone / iOS | 17.0 | `com.example.WristWords` |
| WristWordsWatch | Apple Watch / watchOS | 10.0 | `com.example.WristWords.watchkitapp` |

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
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO

# 独立验证 Watch Simulator Debug build
xcodebuild build -project WristWords.xcodeproj -scheme WristWordsWatch \
  -configuration Debug -sdk watchsimulator \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath build/watchOS CODE_SIGNING_ALLOWED=NO
```

工程和 Info.plist 由 `project.yml` 重新生成，不提交 `.xcodeproj`、`.generated` 或编译产物。
CI 删除首次生成的工程并重新生成，比较两次结果，再构建并检查 App Bundle 与 companion 关系，最后确认 checkout 无未提交变化。
使用 Runner 默认 Xcode，每次输出实际 macOS、CPU、Xcode、Swift、XcodeGen 和 SDK 信息，未绑定特定 Xcode 安装路径。

当前验证范围仅为工程生成和未签名 Simulator 编译；尚未进行模拟器启动、真机运行、签名或发布验证。
