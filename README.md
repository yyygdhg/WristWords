# WristWords

- Stage 1 — macOS CI environment
- Stage 2 — iOS + watchOS project skeleton
- Stage 3 — local vocabulary review MVP
- Stage 4 — Simulator runtime validation
- Stage 5 — MaiMemo API integration

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

## Simulator 运行验证

`app-build.yml` 保留工程重复生成、8 个核心测试、两个 Simulator Build、companion 检查和干净 checkout 检查，再执行 `scripts/simulator_smoke.py`。

- 使用当前 Xcode 的 `simctl list --json` 查询实际安装的 Runtime、可用设备和配对信息。
- 根据构建产物的最低系统版本动态选择可用配对，优先选择较新的已安装 Runtime；不绑定型号、UDID 或 Xcode 安装路径。
- 用 `simctl boot` 启动设备并打开当前 Xcode 的 Simulator 应用，再以流式日志的 `bootstatus -b` 等待启动；随后分别 `install` 安装、`get_app_container` 确认安装、`launch` 启动 iPhone 和 Watch App。
- 两个 App 各观察 20 秒，检查原始启动 PID 仍是对应的 App 进程，并检查本次新生成的 App crash report。
- 使用 `simctl io screenshot` 捕获两个实际屏幕；不修改 Stage 3 UI。
- 将 `iphone.png`、`watch.png`、Runtime/设备信息、运行报告及 App stdout/stderr 上传到 `simulator-runtime-<run id>-<attempt>` Artifact，保留 14 天。失败时也保留已产生的证据，Smoke Test 的错误不会被忽略。

在 GitHub Actions Run 页面底部的 **Artifacts** 下载截图，即可在 Windows 查看。

首次实测通过：[Simulator runtime validation Run](https://github.com/yyygdhg/WristWords/actions/runs/37478954786)。动态选中了 iPhone 17 / iOS 26.5 与 Apple Watch Ultra 3 (49mm) / watchOS 26.5，两个 App 均成功安装、启动并通过 20 秒存活检查；两张截图 Artifact 已生成并检查，iPhone 显示 5 个 Mock 单词，Watch 显示初始 `1 / 5` 和 `engagement`。

当前验证覆盖安装、启动和短时间运行，并提供初始页面截图供查看；尚未自动点击 Watch 评价按钮，也未验证长时间稳定性、真机运行、签名或发布。

## 墨墨 API（iPhone 开发阶段）

数据来源统一为 `VocabularySource.loadWords()`，输出 `[VocabularyWord]`，StudySession 无需知道来源。`MockVocabularySource` 保留原来的 5 个单词；iPhone 启动始终加载 Mock，不会因为存在已保存的 Token 而自动发送 API 请求。Watch 继续使用原来的 Mock，不编译 iPhone 的网络或 Keychain 代码。

### 官方能力与转换

依据 [墨墨官方 OpenAPI 规范](https://open.maimemo.com/api_bundle.yaml) 使用生产服务 `https://open.maimemo.com/open`：

- `POST /api/v1/memo/vocabulary/query`：按公开示例单词拼写批量查询，读取返回的 `id` 和 `spelling`。
- `GET /api/v1/memo/interpretations?voc_id=…`：读取该单词下自己创建的个人释义，忽略已删除内容并去重。
- 请求凭证只放在 `Authorization: Bearer …` Header，不放在 URL。
- 官方词汇响应没有音标字段，释义接口也不是完整词典接口。模型的 `phonetic` 留空；没有个人释义时 `meaning` 留空，iPhone 明确显示“官方 API 未提供音标 / 暂无个人释义”，不混用 Mock 字段冒充真实数据。
- 解码支持规范中的 payload 及 [官方 CLI](https://github.com/maimemo/memo-api-cli/blob/main/src/client.ts) 支持的 `data` envelope。缺失 ID/拼写的行会跳过；无法解析或全部异常的响应进入错误状态。

当前验证查询 `engagement`、`maintain`、`abandon`、`significant`、`approach` 这 5 个拼写，不读取公测的今日学习列表，不写入或修改墨墨账号数据。

### 本机输入凭证

在 iPhone 页面展开“请求凭证（仅本机）”，把自己的墨墨原始请求凭证粘贴到 SecureField：

1. 可选择“保存到 Keychain”。使用 `WhenUnlockedThisDeviceOnly`，关闭同步，不保存到 UserDefaults、源码或明文文件；保存成功后清空输入框。
2. 点击 `Test Connection / 加载真实数据`。输入框有值时仅使用本次输入；输入框为空时读取本机 Keychain。成功后显示 `Data Source: MaiMemo API`、实际数量及返回的单词。
3. 可点击“删除已保存凭证”，或“使用 Mock 数据”切回离线模式。

Keychain 不可用时显示错误，不退回明文存储；仍可输入凭证后仅在本次运行中测试。没有 Token、网络错误、HTTP 错误、JSON 错误及 API 拒绝均显示基本错误状态，不打印原始响应、请求 Header 或 Token。

凭证由用户在自己的设备或 Simulator 中手动提供。**不使用 GitHub Secret、环境变量注入或 CI 真实 API 请求**；没有完整 OAuth/OIDC，没有 Token 上传或同步到 Watch。此入口仅用于当前开发阶段，不是正式多用户授权流程。

### 自动测试与验证边界

- 30 个测试：原有 8 个 StudySession 测试，加上 Mock 数据接口、固定 JSON Fixture 解码/字段转换、异常数据、缺失凭证、HTTP/网络/API 错误、取消以及本机凭证流程的测试。
- API 测试只注入 Stub HTTP 响应，不访问墨墨服务器；Fixture ID、凭证占位和释义均为合成测试数据，不包含真实用户数据。
- Keychain 流程的单元测试使用内存 Stub；iPhone 编译使用系统 Security 框架的真实 Keychain 实现。
- CI 继续从干净 checkout 生成工程、执行测试、编译两端、检查 companion、实际安装/启动 Simulator 并截图，始终使用 Mock。Artifact 仅包含 CI 的 Mock 画面及运行证据。
- 真实请求成功、账号权限、个人释义内容和本机 Keychain 行为需要用户手动粘贴凭证后最终验证；当前自动测试不等于真实 API 已验证成功。
