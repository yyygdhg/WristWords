# WristWords

- Stage 1 — macOS CI environment
- Stage 2 — iOS + watchOS project skeleton
- Stage 3 — local vocabulary review MVP
- Stage 4 — Simulator runtime validation
- Stage 5 — MaiMemo API integration
- Stage 6 — iPhone to Watch vocabulary sync
- Stage 7 — Watch to iPhone study result sync

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
Shared/                    单词、StudySession、Snapshot 与学习事件编解码
WristWords/App/            iPhone 单词列表、凭证入口与 Watch Results
WristWords/Data/           数据源、列表状态与内存中的 Watch Results
WristWords/Sync/           iPhone WCSession delegate
WristWordsWatch/App/       Watch App 入口与背词页面
WristWordsWatch/Study/     学习状态与待排队事件
WristWordsWatch/Sync/      Watch WCSession delegate 与后台任务完成
Tests/                    核心逻辑、API Fixture、双向同步的 XCTest 测试
project.yml               三个 Target 的源码归属、设置与 Scheme
```

StudySession 仍是值类型，由 WatchStudyModel 保存。Restart 清空当前背词结果并建立新的 Session ID，已产生的待传输事件继续保留。iPhone 接收结果仅存于当前 App 运行周期的内存；没有历史数据库或学习调度算法。
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
- 根据构建产物的最低系统版本动态选择可用配对，优先选择较新的兼容已安装 Runtime；不绑定型号、UDID 或 Xcode 安装路径。编译使用当前 Xcode/SDK。
- 用 `simctl boot` 启动设备并打开当前 Xcode 的 Simulator 应用，再以流式日志的 `bootstatus -b` 等待启动；先分别 `install` 安装、`get_app_container` 确认两端安装完成，然后再 `launch` 启动 iPhone 和 Watch App，保证 WCSession 激活时两端环境已经准备好。
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

## iPhone → Watch 单向词汇同步

点击 iPhone 的 **Send to Apple Watch**，发送页面当前已经加载的 `[VocabularyWord]`；来源可以是 Mock 或 MaiMemo API，Watch 不需要知道来源。加载中或请求失败时不发送列表。

### 传输与生命周期

- 使用 Apple 官方 [WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity/wcsession) 的 `updateApplicationContext`，传送完整的最新词汇快照。系统替换尚未投递的旧快照并安排后台传输，不要求 Watch 当前可达或保持前台。
- 快照用 Codable JSON 编码为 Data，放入 property-list 兼容的 context。只包含 `version`、`transferID` 以及单词的 `id`、`term`、`phonetic`、`meaning`；没有 Token、Keychain、Authorization Header 或数据源对象。
- iPhone 等待 WCSession 激活，并检查配对及 Watch App 安装状态。成功提交只显示“已提交，等待 Watch 接收”，不冒充已经送达；没有 Watch 或提交失败显示简单反馈。
- Watch 在 App 初始化时激活并保留 WCSession delegate，在激活后读取 `receivedApplicationContext`，并处理新 context 的 delegate 回调。解码与界面状态更新在主线程完成。
- 每次新的有效快照重新创建 StudySession，从 `1 / N` 开始；相同 transferID 的重复投递不会重置已有进度。评价、完成和 Restart 保留。
- 尚无同步数据时使用原有 Mock fallback。有效空列表显示等待新单词；无效 JSON、字段、重复 ID 或未知格式保留当前 Session，不 Crash。
- 不自行持久化单词或评价，只利用系统的最新 received context 在后续启动时恢复词汇列表。学习进度仍在内存中。

### CI 验证及真机边界

46 个测试保留 Stage 5 的全部 30 个测试，新增单词/快照编码、多个字段及 Unicode、property-list 传输、空列表、无效 payload、字段白名单、Watch Session 创建、重复投递、数据替换与背词 Restart 测试。

现有 XcodeGen、两端 Build、companion、Runtime 和干净 checkout 验证继续保留。额外的 `simulator_sync_smoke.py` 在已经启动的配对 Simulator 中重新启动两端，iPhone 通过同一发送方法传送**顺序反转的 5 个 Mock 单词**，Watch 必须通过真实 WCSession 接收；脚本不直接给 Watch 注入词汇。

此探测只在 Debug Simulator 且带 `--wristwords-sync-smoke` 参数时启用，不进行 API 请求。它比较两端的 transferID、数量和首词 ID，生成 `sync-runtime-report.json`、`iphone-sync.png` 与 `watch-sync.png`，一并上传已有 Runtime Artifact；报告与截图仅包含 CI Mock 数据。

首次 Runner 实测：46 个测试及两端 Build、安装、启动均通过；WCSession 报告 `isWatchAppInstalled = false`，所以**没有实际验证跨设备投递**，同步报告为 `not-verified`。此结果不计为同步 PASS；仍需实体配对设备验证。探测保留原生配对/安装检查，不修改 Simulator 注册数据库或注入 Watch 数据。

Runner 冷启动可能耗时较长，单设备 `bootstatus` 最多等待 10 分钟，基础 Runtime 步骤最多 25 分钟。先准备并安装两端，再启动 App；仍保留动态选择、超时失败、安装/Launch、进程存活和崩溃检查，没有绕过系统迁移或修改 Simulator 数据库。

应用验证使用官方标准 `macos-26-intel` Runner，以避开实际观察到的 ARM64 Runner 容量不足；Stage 1 环境 Workflow 仍使用 `macos-latest`。公开仓库的这两种标准 Runner 均属于 [GitHub 免费托管环境](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)，不使用 larger 或 self-hosted Runner。

若 Simulator 未激活配对传输或在 90 秒内没有投递，报告明确写 `not-verified`；基础 Runtime 和自动测试仍必须通过。收到错误内容、payload 被拒绝或 App 退出会让 CI 失败，不伪造成功。Apple 的[官方示例](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)要求使用实体 iPhone 和 Watch 测试，因此后台、断连后延迟投递和设备重启仍需真机验证。

Stage 6 的范围不包含评价回传；Stage 7 的增量见下文。凭证同步、Watch API 请求、历史数据库、正式 OAuth、签名和发布仍未实现。

## Stage 7 — Watch to iPhone study result sync

### 学习事件与 Snapshot 关联

Watch 对收到的词汇点击“忘记 / 模糊 / 认识”时，先执行原 StudySession 的评价与下一词，再生成一个 `StudyResultEvent`：

- `version = 1`、独立的 UUID `id`：同一事件重试时保留相同 ID。
- `transferID`：原 `VocabularySnapshot.transferID`，关联下发批次。
- `sessionID`：本次背词的 UUID；收到新 Snapshot 或点击 Restart 时更新，重复接收同一 Snapshot 不更新。
- `sequence`：本次 Session 内从 1 开始的评价顺序。
- `result`：复用现有 `StudyResult`，仅有 `wordID` 和 `StudyRating`。传输评级代码为 `forgotten` / `uncertain` / `known`，界面保留中文。

没有收到 iPhone Snapshot 时，Mock fallback 继续正常背词，评价只留在 Watch，不虚构下发批次。

### 后台排队与接收

复用两端原 WCSession 生命周期和 delegate，不建立第二个 WCSession。iPhone delegate 在 App 初始化时激活，支持接收后台启动时的事件；Watch 完成系统 WatchConnectivity 后台任务，避免悬挂的后台任务耗尽运行预算。

每条事件编码成 JSON Data，放在 property-list 兼容的 user-info 字典中，使用 Apple 官方 [`transferUserInfo`](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:)) 独立排队。该机制保留多条事件并在 App 挂起后继续传输，不要求 iPhone 此刻可达；原单词同步继续使用 `updateApplicationContext`。

尚未激活 WCSession 时，事件暂存在 Watch 内存，连接激活后再入系统队列；只在调用系统排队 API 后移出内存待发列表，不取消旧事件。系统完成回调报错时保留同一事件供 `Retry result sync`、后续评价或连接激活重试。状态只说明“已排队，等待 iPhone 接收”，不将排队视为收到。

iPhone 的 [`didReceiveUserInfo`](https://developer.apple.com/documentation/watchconnectivity/wcsessiondelegate/session(_:didreceiveuserinfo:)) 回调切回 MainActor，在 `WatchResultsModel` 中解码与记录。先按事件 UUID 去重，再拒绝同一 Session/序号的冲突事件及 Session 跨 Snapshot 的异常关联。已知 Snapshot 还检查序号与单词位置匹配；无效、未知版本或冲突数据不改变已有结果。

iPhone 的 **Watch Results** 按 Snapshot 分组，显示单词、评价、Session ID 和序号；每个 Session 按序号排列，延迟到达的旧批次不混入新批次。当前运行周期已发送的 Snapshot 用于解析单词拼写；iPhone 重启后收到旧批次事件时单独分组，缺少本地词表便显示 wordID。

### 测试、Simulator 与保存边界

- 共 72 个自动测试：保留 Stage 1～6 的 46 个，新增 26 个。覆盖三种评级与 Unicode、JSON/property-list 编解码、字段白名单、异常与未知版本、批次/Session/顺序关联、多事件、重复与冲突拒绝、延迟与乱序事件、Restart，以及未就绪/部分排队/失败重试时保留事件。
- Core Tests 使用固定数据与注入的排队闭包，不调用真实墨墨 API 或真实 WatchConnectivity。CI 继续使用 Mock，Artifact 不包含真实用户数据或凭证。
- 保留工程重生成、两端 Build、companion、两端 Simulator Boot/Install/Launch、截图和干净 checkout 检查，以及 Stage 6 的实际 WCSession Snapshot probe。
- Apple 官方文档明确表示 Simulator 不支持 `transferUserInfo`，且不调用 `didReceiveUserInfo`。Stage 7 在 `sync-runtime-report.json` 的 `studyResultSync` 与 Actions Summary 中明确记录 **not-verified**，不注入结果、不改 Simulator 数据库、不把单元测试或系统入队冒充真实跨设备成功。跨设备回传请用实体配对 iPhone + Watch 验证。
- iPhone 已收到结果和去重记录只在本次运行周期中保存；App 关闭后不恢复历史记录。Watch 尚未移交系统的待发事件和显式传输失败后的重试列表也仅在内存；强制结束 App 时这部分不保证恢复。已移交的后台传输由系统管理，短暂断连时不主动丢弃或取消。
- 真机仍需验证：前台评价回传、连续多词、iPhone 不可达后的延迟投递、后台唤醒、失败重试、Restart、新 Snapshot 与旧批次的交错到达。App 重启历史恢复与长期持久化留待后续阶段。

本阶段不写回墨墨、不修改学习进度，不传 Token / Keychain / Authorization Header，不引入数据库、SRS、OAuth、签名或发布。
