# 验证记录

2026-10-24，Windows x86-64：

- 官方稳定版 `moon 0.1.20261023 (3778465)`、`moonc v0.10.17+d971670cd`、`moonrun 0.1.20261023`。
- 工具链 ZIP 的 SHA-256 与官网下载的 `.sha256` 文件一致。
- `moonbitlang/async 0.22.5` 使用本机已有同版本缓存，未为本项目访问 Mooncakes 站内搜索。
- Wasm、Wasm-GC、JavaScript 的严格检查及各 22 项核心/文档测试通过；Wasm CLI 真正处理 Chinook 全部 11 张表、15,607 行，独立检查行列数量、客户→发票→明细引用和保留业务值。复合引用另覆盖元组匹配、分量规则、部分 null 和行重排。
- bundle 测试覆盖精确数字往返、生成的 Int64 边界批次、所有截断前缀、摘要损坏、策略指纹、报告/约束复核及输出预算。Wasm 文件工作流覆盖全量数据、目标不覆盖、坏输入不发布、发布错误清理及再次成功。

本机没有 MSVC/Windows SDK。Native 的严格编译检查已执行，但本机 Native 构建因工具链缺失未完成；切换 GCC 也不能满足当前 Windows 异步运行时要求，未将这些尝试记为成功运行。CI 使用各操作系统默认 Native 路径，Windows 配置 MSVC，真正运行测试与 CLI。远端 CI 的实际结论以对应提交的 Checks 为准。

首个提交 `6177f27` 的[远端检查](https://github.com/vivid-oi/MBTRelMask/actions/runs/40094658499)全部成功：三个可移植目标，以及 Linux、macOS、Windows 三个 Native 运行。该提交包含 13 项测试；后续新增能力须查看其各自的 Checks。

复合引用提交 `e544620` 的[远端检查](https://github.com/vivid-oi/MBTRelMask/actions/runs/40094827517)全部成功，同样包含三个可移植目标及三个操作系统的 Native 运行，共 17 项测试。

`dev/verify.mbtx` 执行格式、接口漂移、严格检查、测试；Native / Wasm 另运行完整 Chinook 命令并检查行列数量、保留业务值及实际联表引用，再调用 `dev/bundle_workflow.mbtx` 进行文件导出与失败恢复验证。所有开发自动化均为 `.mbtx`，不要求 Python、数据库服务或 Node 程序参与 Native 演示。
