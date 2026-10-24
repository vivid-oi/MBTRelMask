# 多表 CSV 工作流

CSV 入口复用策略中的类型、全部列、主键、唯一约束和外键，不推断类型，不丢未知列，不把错误值自动改为 null。

- `Plan::import_csv(Map[String, String]) -> String`：表名对应 CSV 文本，返回验证后的规范 JSON，仍含原值。
- `Plan::export_csv(String) -> Map[String, String]`：验证输入 JSON 后输出逐表 CSV，本方法本身不替换数据。

对外分享前应调用 `transform`，或从 `verify_bundle` 得到完成结果再导出 CSV。CLI 将这些步骤连成完整流程。

## 从已有导出进入

准备一个目录，其中 `manifest.json` 明确关联表名和同目录文件名：

```json
{"accounts":"accounts.csv","events":"events.csv"}
```

必须提供策略的全部表，空表也提供表头。文件名只接受 ASCII 字母、数字、点、下划线、连字符，排除 `.` 和 `..`，不接受绝对路径或子路径。目录内不在清单中的文件不会自动读取。

```sh
# 先设置 RELMASK_KEY
moon run apps/relmask --target wasm -- export-csv examples/tenants/policy.json examples/tenants/csv tenants.bundle.json
moon run apps/relmask --target wasm -- verify examples/tenants/policy.json tenants.bundle.json
moon run apps/relmask --target wasm -- unpack-csv examples/tenants/policy.json tenants.bundle.json tenants-output
```

`export-csv` 读取并验证所有 CSV，替换后发布 bundle。`unpack-csv` 无需秘密，先复核 bundle，再输出到新目录。目录包含 `manifest.json`、`report.json` 和 `table-0.csv` 等文件；序号按表名排序，清单保留真正表名，Unicode 表名不会直接变成文件路径。

输出先在同级私有暂存目录内完整生成，文件同步、关闭后使用不覆盖目标的重命名发布。已有文件和目录均拒绝覆盖，普通错误清理暂存内容，无法清理时报告路径。POSIX 目录请求 0700、文件请求 0600，Windows 使用系统 ACL。强制终止、断电、目录同步和不可信共享目录的边界与 [bundle 契约](bundles.md)相同。

## 支持的约定

| 项目 | 明确行为 |
| --- | --- |
| 编码 | 库接受 String；CLI 严格 UTF-8，可带文件开头 BOM |
| 表头 | 必须有，列名精确匹配，可重排列顺序；重复、未知、缺失列拒绝 |
| 分隔与引号 | 逗号、双引号；内嵌双引号用 `""`，引号内允许逗号和换行 |
| 记录终止 | CRLF 或 LF，末尾换行可省略；引号外孤立 CR 拒绝 |
| null | **未加引号的 `\N`**，只允许可空列 |
| 文本 | `"\N"` 是字面量；空字段和 `""` 是空文本，保留空白、Unicode 和前导零 |
| 数字 | JSON 数字字面量，保留拼写；integer 还须为 Int64 整数字面量 |
| 布尔 | `true`、`false`，不接受 0/1、大小写变体或空白包裹 |
| 空记录 | 不跳过，视为一个空字段，仍检查表宽、类型和约束 |
| 导出 | 策略列顺序、原行顺序、CRLF；表头和文本总加引号，null 为未加引号的 `\N` |

数字/布尔不能写 `null` 代替 null 标记，也不能带首尾空白。不支持数组/对象单元格、自动编码检测、分号/Tab 分隔或自定义转义。失败返回表、逻辑记录、列位置诊断，没有部分结果。空白、引号选择和行终止写法不要求原样保持；类型、值、精确数字表示、null 与空文本区别必须保持。

CSV 输入合计、转换出的 JSON、CSV 输出合计都受 `max_input_units` 限制；所有表合计行数受 `max_rows` 限制。扩张过量拒绝。CLI 另限制清单 4 MB、CSV 输入/输出合计 64 MB、bundle 128 MB。向其他导入器交付时须保留策略并配置相同 null/类型约定。

## 验证与生态边界

```sh
moon run dev/csv_workflow.mbtx -- wasm
```

该流程以完整 Chinook 完成 JSON → 替换 bundle → CSV 目录 → 再导入并替换 → bundle，独立检查 11 表、15,607 行及保留业务数值；另验证复合键样本、不覆盖、清单路径拒绝、发布失败清理和恢复。再次替换会改变 token 和重编号，不要求两份 bundle 相同。库测试另外验证未替换数据的精确 CSV 往返。

格式边界参考 [RFC 4180](https://www.rfc-editor.org/rfc/rfc4180)，采用上面的 UTF-8/null profile，不声称支持所有 CSV 方言。生态已有 [NyaCSV](https://github.com/moonbit-community/NyaCSV)，其公开 `CSV::data` 返回字符串矩阵。本项目未建立通用 CSV 包或公开 tokenizer；私有读取层保留是否加引号的信息以区分 null 标记和字面量，将类型与多表关系检查放在 Plan 的导入/导出边界内。未复制 NyaCSV 的代码。
