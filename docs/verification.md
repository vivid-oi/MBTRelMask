# 验证记录

2026-10-24 至 2026-10-25，Windows x86-64：

- 官方稳定版 `moon 0.1.20261023 (3778465)`、`moonc v0.10.17+d971670cd`、`moonrun 0.1.20261023`。
- 工具链 ZIP 的 SHA-256 与官网下载的 `.sha256` 文件一致。
- `moonbitlang/async 0.22.5` 使用本机已有同版本缓存，未为本项目访问 Mooncakes 站内搜索。
- Wasm、Wasm-GC、JavaScript 的严格检查及各 45 项核心/文档测试通过；Wasm CLI 真正处理 Chinook 全部 11 张表、15,607 行。聚合裁剪检查指定反向外键、行数/歧义拒绝及发票全部明细。MATCH FULL 覆盖全 null、非 null、部分 null、未知模式、CSV、子集和 bundle 往返。状态测试覆盖三十批追加、删除重现、认证/策略失败、编号溢出、畸形认证状态和恢复；全量 Chinook 增加艺术家后旧行输出逐行不变。比较测试覆盖重排行、复合/大整数主键、新增/删除、精确数值表示变化、非泄露和错误恢复，真实 CLI 验证退出码 0/3/1。
- CSV 覆盖精确数字和 null/空文本/字面量区别、Unicode、引号、换行、畸形输入、表头/宽度/类型、全批预算和 0–40 行生成往返。文件流程以完整 Chinook 验证 CSV 导出再导入、业务值保留、目录不覆盖、路径清单拒绝、错误清理和恢复。
- 关系裁剪包含复合/唯一目标、循环、千层链、幂等性和种子顺序不影响结果；真实 Chinook 工作流从 15,607 行得到 11 行父依赖闭包，再完成替换、文件发布和复核。
- bundle 测试覆盖精确数字往返、生成的 Int64 边界批次、所有截断前缀、摘要损坏、策略指纹、报告/约束复核及输出预算。Wasm 文件工作流覆盖全量数据、目标不覆盖、坏输入不发布、发布错误清理及再次成功。

本机没有 MSVC/Windows SDK。Native 的严格编译检查已执行，但本机 Native 构建因工具链缺失未完成；切换 GCC 也不能满足当前 Windows 异步运行时要求，未将这些尝试记为成功运行。CI 使用各操作系统默认 Native 路径，Windows 配置 MSVC，真正运行测试与 CLI。远端 CI 的实际结论以对应提交的 Checks 为准。

首个提交 `6177f27` 的[远端检查](https://github.com/vivid-oi/MBTRelMask/actions/runs/40094658499)全部成功：三个可移植目标，以及 Linux、macOS、Windows 三个 Native 运行。该提交包含 13 项测试；后续新增能力须查看其各自的 Checks。

复合引用提交 `e544620` 的[远端检查](https://github.com/vivid-oi/MBTRelMask/actions/runs/40094827517)全部成功，同样包含三个可移植目标及三个操作系统的 Native 运行，共 17 项测试。

关系裁剪提交 `bd30d67` 的[远端检查](https://github.com/vivid-oi/MBTRelMask/actions/runs/40095683579)全部成功，包含三个可移植目标和三个操作系统的 Native 实际运行，共 27 项测试。

聚合子集 `06c1153` 的[检查](https://github.com/vivid-oi/MBTRelMask/actions/runs/40117632956)与 MATCH FULL `6a61cfb` 的[检查](https://github.com/vivid-oi/MBTRelMask/actions/runs/40117745136)均全部成功，包含三种可移植目标与 Linux/macOS/Windows Native 实际运行。

状态映射 `122795d` 的[检查](https://github.com/vivid-oi/MBTRelMask/actions/runs/40118382763)全部成功，包含 41 项测试及完整文件流程，覆盖同样六项矩阵任务。

`dev/verify.mbtx` 执行格式、接口漂移、严格检查、测试；Native / Wasm 另运行完整 Chinook 命令，并运行 bundle、subset、csv、state 四套文件工作流。所有开发自动化均为 `.mbtx`，不要求 Python、数据库服务或 Node 程序参与 Native 演示。
