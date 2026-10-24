# PostgreSQL 精度与约束探针

此处数据为本项目构造的公开测试输入，按仓库 Apache-2.0 协议提供，包含四条有外键关系的记录：Int64 两端、自引用循环、1e400、27 位小数、null、布尔和含引号/CRLF/中文/反斜杠的文本。额外的 2、10 用于检查数值排序，避免测试查询误用 TEXT 别名排序。文本中的 SQL 片段是普通字段值。

设置 README 中的公开示例 RELMASK_KEY 后：

```sh
moon run apps/relmask --target wasm -- export examples/sql/policy.json examples/sql/data.json probe.bundle.json
moon run apps/relmask --target wasm -- unpack-sql examples/sql/policy.json probe.bundle.json probe.sql relmask_probe
psql -X -v ON_ERROR_STOP=1 -f probe.sql
psql -X -c 'SELECT id, parent, value, label FROM relmask_probe.probe ORDER BY id;'
```

这里策略全部 keep，便于核对值；它不用于隐藏真实敏感数据。需 UTF-8 PostgreSQL 18 和全新 schema。完整自动验证同时导入 Chinook 并检查约束错误，见 [SQL 工作流](../../docs/sql.md)。
