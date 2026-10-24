# PostgreSQL 测试库导出

把已经替换并复核的 bundle 导入独立测试 schema，供查询和应用集成测试使用。库与 CLI 只生成 SQL，不连接数据库；实际导入由调用者的 psql 完成。当前验证目标是 PostgreSQL 18、UTF-8 数据库、默认 63 字节标识符上限。

## 完整流程

先按 README 的方式设置 RELMASK_KEY，再执行：

```sh
moon run apps/relmask --target wasm -- export examples/chinook/policy.json examples/chinook/data.json chinook.bundle.json
moon run apps/relmask --target wasm -- unpack-sql examples/chinook/policy.json chinook.bundle.json chinook.sql relmask_fixture
psql -X -v ON_ERROR_STOP=1 -f chinook.sql
psql -X -c 'SELECT count(*) FROM relmask_fixture."InvoiceLine";'
```

最后一个查询应返回 2240。psql 使用标准 PGHOST、PGPORT、PGUSER、PGDATABASE 等连接配置。目标 schema 必须不存在，用户须具备创建 schema 的权限。文件目的地也必须不存在；CLI 在完整验证和生成后才发布文件。生成失败不留下部分 SQL，已有文件保留。

unpack-sql 的形式为 `unpack-sql POLICY BUNDLE DEST [SCHEMA]`，默认 schema 为 relmask_fixture。它先验证策略指纹、数据摘要和关系约束。无需原数据或秘密。bundle 的无秘密摘要不能认证发布者。

库入口：

```text
Plan::export_sql(source : String,
                 schema? : String = "relmask_fixture",
                 max_output_units? : Int = 64000000) -> String raise MaskError
```

source 是完整数据集 JSON。这个方法验证数据并生成 SQL；要替换数据，应传入 transform 或 verify_bundle 返回结果的 to_json。直接传入原始数据会原样导出其值。

## 保留语义与失败边界

- 输出单个 BEGIN / COMMIT 事务，创建全新 schema。建表后插入数据，最后增加外键，因此支持循环和任意策略表顺序。现有 schema 导致错误；不生成 DROP 或覆盖语句。使用 ON_ERROR_STOP，失败时会话退出，事务回滚。
- text 映射为 TEXT COLLATE pg_catalog."C"，integer 为 BIGINT，decimal 为无精度约束的 NUMERIC，boolean 为 BOOLEAN。保留 null、主键、两种 null 唯一键语义、MATCH SIMPLE / FULL、非空和字符数上限。外键为 DEFERRABLE INITIALLY DEFERRED。
- 文本转为 UTF-8 十六进制后由 PostgreSQL 解码，保留引号、反斜杠、CR/LF 和 Unicode。标识符逐个加双引号。固定 search_path 为 pg_catalog。NUL、不能无损编码的文本、空/控制字符/超过 63 UTF-8 字节的标识符、pg_ 开头的 schema 均拒绝。
- 数字不经 Double 转换。Int64 两端及大数/长小数保留数值；数据库可改变原始 JSON 的指数、尾零等书写形式。负零因符号无法保留而拒绝。NUMERIC 导出采用保守边界：系数总位数最多 147455，整数位与指数之和最多 131072，小数位减指数最多 16383，指数绝对值最多 1000000。越界拒绝，不舍入或截断。
- 输出预算按 UTF-16 code units 计算，默认 64000000，可设为 1–128000000；仍受原有输入和总行数预算约束。相同策略、数据顺序和参数生成相同 SQL。

常见诊断：sql_text_nul、sql_utf8、sql_identifier、sql_schema_reserved、sql_negative_zero、sql_numeric_range、sql_output_limit、sql_limit_range，附数据或配置位置，不附原始值。数据库权限、磁盘等导入错误由 psql 报告。

不读取原数据库 DDL，也不恢复触发器、索引、序列、视图、权限、扩展、时间类型或策略未声明的 CHECK。日期规则的结果仍为 TEXT。没有 SQL 导入解析器或数据库到原 JSON 表示的往返保证。只验证 PostgreSQL 18；其他数据库和 PostgreSQL 版本尚未验证。

## 可复现验证

```sh
moon run dev/sql_workflow.mbtx -- wasm
moon run dev/sql_workflow.mbtx -- native moon --database
```

第一条只需 MoonBit，检查真实 Chinook 文件发布、已有文件不覆盖和 NUL 拒绝后的无残留。第二条另需 psql 和一个专用 PostgreSQL 18 UTF-8 测试库，使用标准 PG 连接配置；可用 RELMASK_PSQL 指定客户端绝对路径。它创建 relmask_fixture 和 relmask_probe，仅在本次导入成功后清理其创建的 schema；遇到已有同名 schema 会失败并保留它。

数据库验证逐表核对 Chinook 全部 15607 行，检查联表引用；另用公开探针检查 Int64 边界、1e400、27 位小数、带 SQL 片段/Unicode/控制字符的文本、自引用循环，并实际触发唯一键、外键、长度、非空错误，再检查已有 schema 拒绝覆盖。探针来源和操作见 [示例](../examples/sql/README.md)。CI 使用独立 postgres:18 服务，无需私有基础设施。
