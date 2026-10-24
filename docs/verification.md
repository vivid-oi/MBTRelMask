# 验证记录

2026-10-24，Windows x86-64：

- 官方稳定版 `moon 0.1.20261023 (3778465)`、`moonc v0.10.17+d971670cd`、`moonrun 0.1.20261023`。
- 工具链 ZIP 的 SHA-256 与官网下载的 `.sha256` 文件一致。
- `moonbitlang/async 0.22.5` 使用本机已有同版本缓存，未为本项目访问 Mooncakes 站内搜索。
- Wasm、Wasm-GC、JavaScript 的严格检查及各 13 项核心/文档测试通过；Wasm CLI 真正处理 Chinook 全部 11 张表、15,607 行，独立检查行列数量、客户→发票→明细引用和保留业务值。

本机没有 MSVC/Windows SDK。Native 的严格编译检查已执行，但本机 Native 构建因工具链缺失未完成；切换 GCC 也不能满足当前 Windows 异步运行时要求，未将这些尝试记为成功运行。CI 使用各操作系统默认 Native 路径，Windows 配置 MSVC，真正运行测试与 CLI。远端 CI 的实际结论以对应提交的 Checks 为准。

`dev/verify.mbtx` 执行格式、接口漂移、严格检查、测试；Native 另运行完整 Chinook 命令并检查行列数量、保留业务值及实际联表引用。所有开发自动化均为 `.mbtx`，不要求 Python、数据库服务或 Node 程序参与 Native 演示。
