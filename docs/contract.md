# 数据契约

策略对象只接受 `tables`、`max_rows` 和 `max_input_units`。未知选项是错误，不是扩展槽。

每张表指定 `name`、`columns`、非空 `primary`，可选 `unique` 和 `references`。一列指定 `name`、`type`、`rule`，以及可选 `nullable`（默认 false）、`max_length`（Unicode 标量数量，只适用于 text）。表、列和键内名称不得重复。

类型为 `text`、`integer`、`decimal`、`boolean`。integer 要求十进制整数字面量和 Int64 范围；`1.0` 不能作为 integer 键。decimal 原始数字表示可精确保留，但不能用于键。JSON 数组或对象单元格尚不支持；输入不能包含重复对象字段。

规则：

| JSON | 行为 |
| --- | --- |
| `"keep"` | 保留值及数字表示 |
| `"null"` | 清空非 null 值，仅允许可空列 |
| `{"replace":"text"}` | 常量替换 text；仍须通过所有约束 |
| `{"token":{"domain":"d","prefix":"","suffix":""}}` | text → 前缀 + 32 个小写十六进制字符 + 后缀 |
| `{"reindex":1000}` | integer → 从指定起点开始的一一编号 |

null 始终保持 null。缺失字段与 null 不同，缺失即拒绝。每列都要显式指定规则。未知表、未知字段不会被丢弃。

外键写作 `{"columns":["customer_id"],"table":"customers","target":["id"]}`。目标必须是声明的主键或唯一键，两端类型及规则必须一致。同一 token domain 的前后缀也必须一致。外键连通列共享整数映射；自引用与循环引用不依赖表的拓扑顺序。

主键不允许 null。唯一约束采用 NULLS DISTINCT：包含 null 的元组不参与重复检查。复合外键按列位置对应，非空两端列数必须相等，每一对类型和规则都要一致。检查完整元组，不能把分量分别匹配到不同父行。外键采用 MATCH SIMPLE：任意分量为 null 就不要求父行，其余非 null 分量仍执行自己的转换。字符串精确匹配，不自动去空白、忽略大小写或做 Unicode 归一化。Int64 键按整数相等，`-0` 与 `0` 相等。

转换前必须验证原始键唯一性和引用，不能掩盖原有错误。转换后重新验证类型、长度和全部声明约束。token 发生碰撞会拒绝，重编号起点加键数量溢出会拒绝，不截断值、不删行、不自动换成 null。

输出按策略中的表/列顺序编码，保留行顺序。JSON 空白和转义写法不保证保持。相同输入、策略、秘密和算法版本产生相同结果；重排同一批次中的行不改变键映射。不同批次的重编号映射不保证相同。

输出扩张后也必须满足 `max_input_units`，超出返回 `output_too_large`，确保导出的结果能按相同策略再次验证。携带报告的单文件格式见 [bundles.md](bundles.md)。

秘密要求至少 32 UTF-8 字节、最多 4096 个字符串 code units。token 输入为 JSON 字符串数组 `["relmask-1", domain, original]` 的紧凑 UTF-8 表示。前后缀不参加 HMAC，但策略必须保持 domain 的格式一致。重编号以关联域编号和原键的 HMAC 排序，碰到相同排序分数时以原键打破平局。

默认限制：128 张表，每表 256 列，总行数 100,000，输入 16,000,000 UTF-16 code units，JSON 嵌套深度 64，策略 1,000,000 code units。可配置行数/输入单位上限不超过 100,000,000。CLI 限制策略 4 MB、数据 64 MB，并使用严格 UTF-8 解码和有界读取。

错误类型 `MaskError::Invalid(code~, location~)` 不带输入值。检查报告只包含算法版本、约束检查状态、变更单元格数量和各表行数；不会输出秘密、原值或映射表。库调用在失败时不返回部分转换结果，也不污染 Plan 的后续调用。

不支持 decimal 键、嵌套单元格、数据库排序规则、SQL dump、数据库连接、格式保持加密、增量映射或隐私保证。这些输入必须明确拒绝，不能自动退化。

外键可设 `"match":"full"`：整个引用全部 null 时免匹配，全部非 null 时必须匹配，部分 null 报 `partial_null_reference`。默认或显式 `"match":"simple"` 保持既有行为。其他 match 值拒绝。JSON/CSV 导入、转换前后、bundle 复核、子集选择都检查同一规则；不会自动补全或清空部分键。语义参照 [PostgreSQL 外键文档](https://www.postgresql.org/docs/current/ddl-constraints.html#DDL-CONSTRAINTS-FK)。不模拟完整数据库行为。

多表 CSV 通过同一 Plan 做显式类型转换和约束验证，规则见 [CSV 契约](csv.md)，没有类型推断或失败自动填 null。
