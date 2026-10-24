# 从记录出发裁剪可联表的复现包

`Plan::subset(data, seeds)` 从指定主键记录出发，保留它们及所有递归依赖的父记录。目标可以是父表的主键或唯一键，包括复合元组。自引用和循环使用迭代闭包，不依赖表顺序。不会自动带上父记录的其他子记录，避免一条记录重新扩张成整库。

seeds 是 JSON 对象：表名对应完整主键对象的数组。键对象只接受该表主键列，类型与数据相同。重复种子幂等，未知表/列、缺失分量、null 主键、不存在的记录和畸形 JSON 明确拒绝。种子文本限制 1,000,000 UTF-16 code units。

```json
{"InvoiceLine":[{"InvoiceLineId":1}]}
```

调用前先检查完整源数据的所有约束；裁剪不能用来掩盖未选中记录的错误。输出保留策略表/列顺序和原行顺序，所有声明的表都存在，未选择表可为空。任意分量为 null 的外键按 MATCH SIMPLE 不拉入父行。空种子 `{}` 产生所有表都为空的数据集。

**库返回值仍含原值。** 需要向外分享时继续调用 `transform`；CLI 将两步连在同一次导出中：

```sh
# 先设置 RELMASK_KEY
moon run apps/relmask --target wasm -- export-subset examples/chinook/policy.json examples/chinook/data.json examples/chinook/seeds.json case.bundle.json
moon run apps/relmask --target wasm -- verify examples/chinook/policy.json case.bundle.json
```

此例选择一条发票明细，自动带上发票、客户、员工管理链、歌曲及其分类/专辑/艺术家，再进行替换并发布不覆盖已有目标的 bundle。`dev/subset_workflow.mbtx` 以完整 Chinook 数据运行该流程，检查依赖闭包和排除无关子记录。

子集改变了键集合，因此 `reindex` 结果可能与全量导出不同。subset 通过完整主键指定种子；按字段范围或状态生成种子可用[条件选样](selection.md)。不支持 SQL 文本、自动抽样、行数强行截断或隐私保证。保留父依赖可能引入额外敏感记录，仍需审查逐列策略。裁剪是显式删行，普通 `transform` 仍保留全部行。

## 完整业务聚合

options 为 `{"descendants":[{"table":"InvoiceLine","columns":["InvoiceId"]}],"max_rows":100}` 时，指定外键反向参与闭包，带入发票的全部明细及父依赖。未指定的外键不反向扩张，歌曲不会因此带入其他发票。只有一条外键的子表可用表名字符串简写；多条外键必须用 columns 精确选择，歧义或不存在的引用拒绝。null 不构成匹配，复合引用按完整元组相等。

`max_rows` 是整个最终闭包的上限，正整数且不超过策略行数限制；默认使用策略上限。包含种子和父依赖，超限报 `subset_row_limit`，不会截断。重复种子和环只计一次。空 options 保留原父依赖行为。选得过宽可能扩张到整个关系连通分量，应使用小上限并审查报告。

```sh
moon run apps/relmask --target wasm -- export-aggregate examples/chinook/policy.json examples/chinook/data.json examples/chinook/seeds.json examples/chinook/aggregate.json aggregate.bundle.json
```

该流程保留第一张发票的两条明细；完整源验证、替换、无覆盖发布和 bundle 复核均与普通子集相同。
