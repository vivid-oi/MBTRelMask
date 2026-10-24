# 用差异报告检查样本回归

`Plan::compare_datasets(before, after)` 验证两份完整 JSON 数据，返回不可变 `DatasetDiff`。`is_empty()` 表示数据相等；`to_json()` 给出 `relmask-diff-1` 报告。结果按策略表/列顺序排列，不包含主键值、原值、新值或映射，只包含表名、列名和计数。

匹配采用完整主键元组，Int64 不通过 Double 比较。行顺序、对象字段顺序、JSON 空白和等价字符串转义不影响相等。主键改变算旧行删除加新行新增；新增/删除行不再计入 changed。仅相同主键的行比较单元格，任意字段不同则该行 changed 加一，并分别累加各列的 changed 数量。数字比较保留表示差异，例如 decimal 的 `1e400` 与 `1E400` 记为变化；不做近似或业务数值等价比较。缺字段、重复键、孤儿引用或预算超限拒绝，不生成部分报告。

CLI 比较两份已导出的 bundle，先分别检查摘要、策略指纹和全部约束，无需秘密：

```sh
moon run apps/relmask --target wasm -- compare examples/chinook/policy.json batch-1/bundle.json batch-2/bundle.json
```

退出码 0 表示相同，3 表示不同且报告可用，1 表示数据/策略/I/O 错误，2 表示用法错误。因此可以直接作为 CI 的样本回归门禁；需要不同阈值时用库读取报告自行判断。

报告例形如 `{"format":"relmask-diff-1","equal":false,"tables":[{"name":"Artist","added":1,"removed":0,"changed":0,"columns":[{"name":"ArtistId","changed":0},{"name":"Name","changed":0}]}]}`，实际报告包含策略的全部表和列。

比较的身份是**当前文件里的主键**，无法判断两个不同秘密或不同无状态重编号结果是否来自同一原记录。增量样本应使用同一秘密、精确策略和串行[状态链](state.md)，否则不能把匹配解释成原始业务身份相同。比较结果不是匿名性、来源真实性或发布者认证证明；bundle 的普通完整性摘要可以被重新计算。表名、列名、行数和变化数量仍会透露结构和规模。

完整演练：`moon run dev/state_workflow.mbtx -- wasm`。它使用 Chinook 15,607 行生成带状态的两批样本，第二批新增一位艺术家。自动检查旧行不变、仅 Artist 新增 1、相同样本退出 0、变化退出 3、坏 bundle 退出 1 且无部分 stdout，以及报告中没有新增艺术家的值。三操作系统 Native CI 运行相同流程。
