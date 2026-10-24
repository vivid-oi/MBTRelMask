# 验证记录

本地条件选样验收：74 项测试在 Wasm、Wasm-GC、JavaScript 通过；Native 严格检查、格式和生成接口一致性检查通过。新增测试覆盖 AND/OR、精确 Int64、UTF-16 字典序、null 与 boolean、decimal 比较拒绝、配置及闭包预算、循环和复合键、生成区间与显式种子等价、幂等，以及大主键不受种子序列化预算影响。Wasm 全套文件工作流通过，条件选样独立核对 Chinook 2022 年 83 张发票及 455 条完整明细、金额/日期/数量/引用、默认范围、目标不覆盖、失败不发布与恢复。本机仍无 Native 运行工具链；本轮两笔为本地提交，未推送、未取得新的远端 CI 结果。

本地合并能力检查：65 项测试在 Wasm、Wasm-GC、JavaScript 通过，Native 严格检查通过，格式与生成接口一致。新增用例验证完整复合主键、Int64 两端和相邻大整数、数字表示冲突、跨输入唯一键冲突、独立输入约束、预算、确定性、失败恢复，以及 0–30 行生成数据的幂等/结合性质。Wasm 完整 Chinook 文件流程复用 15607 行并增加一名 Artist；统一转换与直接转换合并数据一致，且验证冲突不发布、目标不覆盖和恢复。本节记录本地验证，不代表这些未推送提交已运行远端 CI。

此前阶段：59 项测试在 Wasm、Wasm-GC、JS 通过；新增可空唯一键、日期平移、批量诊断及 PostgreSQL 导出。格式、生成接口及 Native 严格检查通过。真实工作流覆盖 Chinook 428 个日期，以及同时存在重复键/孤儿引用的诊断、阶段/截断/非泄露和恢复。下方保留此前阶段记录。

2026-10-25，本机 Windows 使用官方 EDB PostgreSQL 18.6 二进制启动隔离、仅监听回环地址的 UTF-8 临时数据库，实际执行 Wasm CLI 生成的 SQL。Chinook 全部 11 表 15607 行导入并逐表计数核对；探针验证 Int64 两端、1e400、27 位小数、引号/CRLF/Unicode/反斜杠、自引用循环，实际触发 UNIQUE NULLS NOT DISTINCT、外键、长度 CHECK、NOT NULL 错误。再次导入拒绝已有 schema，并保留原数据。测试结束数据库已停止。此证据为 Wasm CLI + Windows PostgreSQL 实际运行；本机 Native 仍只有编译检查。

SQL 单元测试另覆盖确定性、数字范围两端/越界/巨大指数、负零、NUL、标识符 UTF-8 字节上限、输出预算、MATCH FULL 和失败后恢复。CLI 工作流验证完整文件发布、目标不覆盖、生成失败不留文件。数据库测试命令和环境要求见 [SQL 导出](sql.md)。CI 增加独立 PostgreSQL 18 服务任务；实际远端状态以该提交 Checks 为准。

38bfd20 的首次远端运行中，六项原有目标任务通过，数据库任务在探针顺序断言失败。检查发现验证查询的 ORDER BY id 指向 SELECT 的 TEXT 别名；这是 PostgreSQL 的输出列优先解析规则。修复为 ORDER BY probe.id，明确使用 BIGINT。增加 2、10 两条记录后，本机 PostgreSQL 18.6 ICU en-US 实例能复现旧查询失败；修复查询随后通过同一工作流。参考：[PostgreSQL ORDER BY](https://www.postgresql.org/docs/18/queries-order.html)。

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

`dev/verify.mbtx` 执行格式、接口漂移、严格检查、测试；Native / Wasm 另运行完整 Chinook 命令，以及 bundle、subset、csv、state、dates、audit、sql 文件工作流。所有开发自动化均为 `.mbtx`，基本文件演示不要求 Python、数据库服务或 Node 程序；显式的 SQL 数据库集成任务另需 PostgreSQL 和 psql。
