# WristWords

Phase 1 — Apple development CI environment

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
- 后续项目计划使用 XcodeGen，从 `project.yml` 生成 `.xcodeproj`。
- 目前还没有正式 iOS/watchOS App，也没有 `project.yml`。
- 当前阶段只验证 macOS、Xcode、Swift、Apple command line tools 和 XcodeGen 工具链，并临时编译运行一个 Swift 程序。

Workflow 支持 `push`、`pull_request` 和手动触发 `workflow_dispatch`。
Swift 测试文件仅在 CI 临时目录生成，运行结束后清理。
