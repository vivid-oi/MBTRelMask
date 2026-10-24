# 按字段条件选取关系样本

复现某年发票、某状态任务或某租户记录时，无需先手工查出所有主键。条件只挑选初始记录，再补齐父依赖和显式指定的子表；闭包包含的依赖记录可以不满足筛选条件。

## 真实工作流

设置 README 中的 RELMASK_KEY 后，选择公开 Chinook 的 2022 年发票、全部明细和依赖：

```sh
moon run apps/relmask --target wasm -- export-selected examples/chinook/policy.json examples/chinook/data.json examples/chinook/select-2022.json year.bundle.json examples/chinook/select-options.json
moon run apps/relmask --target wasm -- verify examples/chinook/policy.json year.bundle.json
```

此固定数据包含 83 张 2022 年发票、455 条对应明细。未选其他年份发票或无关播放列表。客户、员工管理链、歌曲、专辑等父记录按关系补齐。省略最后的 OPTIONS 文件时，只补齐父依赖，不反向带入明细。存在多个外键的子表要明确指定 columns，避免沿错误关系扩张。

```json
{"Invoice":[{"InvoiceDate":{"gte":"2022-01-01","lt":"2023-01-01"}}]}
```

```json
{"descendants":[{"table":"InvoiceLine","columns":["InvoiceId"]}],"max_rows":5000}
```

完整命令形式为 `export-selected POLICY DATA SELECTOR DEST [OPTIONS]`。DEST 必须不存在。先验证完整源数据，再选择、验证闭包、统一转换并发布 bundle；stderr 为原有转换报告。筛选、转换失败时不发布文件。

库入口为 `Plan::subset_where(source : String, selector : String, options? : String) -> String raise MaskError`。返回完整数据集 JSON，所有表都存在，保留策略表/列顺序及原行顺序；结果仍含原值，分享前应调用 transform 或 transform_with_state。options 与 subset 完全相同。

## 条件语义

根对象的键为表名，每张表对应一组 OR 分支；每个分支内的字段，以及一个字段内的多个运算符，均为 AND。多张表的匹配记录共同作为种子。例如，下面选中 id 在区间内且 flag 为 true 的记录，或 note 为空的记录：

```json
{"jobs":[{"id":{"gte":100,"lt":200},"flag":{"eq":true}},{"note":{"is_null":true}}]}
```

| 运算符 | 输入与含义 |
| --- | --- |
| eq / neq | text、integer、boolean 的同类型值，或 null；neq 为 eq 的布尔取反 |
| gt / gte / lt / lte | 非 null 的 text 或 Int64 边界 |
| prefix | text 前缀，区分大小写；空前缀匹配全部非 null 文本 |
| is_null | 布尔值，适用于全部列类型，包括 decimal |

integer 比较始终使用 Int64，包括两端、相邻大整数及 -0 与 0。不能以 1.0 或字符串冒充整数。text 按 UTF-16 code units 字典序比较，公共前缀相同时较短者在前；不使用短串优先排序、数据库排序规则、Unicode 归一化或自然语言排序。ISO 日期范围只是文本范围，适用于示例的一致格式；不解析时区、地区日期或比较不同时区的瞬间。条件针对转换前原值。

null 与 null 相等，与任意非 null 值不等；因此 null 对非 null 的 neq 为 true。范围及 prefix 遇到 null 为 false。这是显式的二值条件语义。decimal 当前仅允许 is_null，精确数值筛选尚未实现；其他运算返回 selector_decimal_unsupported，不改用 Double。

空根对象、空 OR 数组、空分支或空运算符对象均拒绝；无匹配则返回全部表为空的有效数据集。重复或重排 OR 分支不改变选中集合及输出顺序。未知表、列、运算符、重复 JSON 字段和类型不匹配都拒绝，包括未命中或空表上的无效配置。

## 边界与验证

条件文本最多 1000000 UTF-16 code units，最多 64 个 OR 分支、256 个运算符，均按整个配置累计。源数据、最终闭包和输出预算沿用 Plan / options，超限拒绝而非截断。内部直接传递选中行索引，不把大主键重新序列化为种子；显式 subset 的原有种子文本预算保持不变。

条件诊断使用 selector_too_large、empty_selector、selector_type、selector_order_type、selector_decimal_unsupported、selector_branch_limit、selector_predicate_limit 等代码；未知项沿用 unknown_option。位置包含表、分支、列和运算符，不包含筛选值。完整数据验证在筛选前进行，不能用条件掩盖未选中行的原始关系错误。

```sh
moon run dev/selection_workflow.mbtx -- wasm
```

脚本从原始 Chinook 日期前缀独立计算期望集合，核对 83 张发票、455 条明细、金额/数量/时间、输出引用、父依赖与默认不含子表的范围，再检查无覆盖发布、未知操作拒绝、无匹配和失败恢复。CI 的 Native 工作流也执行此脚本。库测试另覆盖生成区间与显式种子结果相同、幂等性、复合键、循环、Unicode、Int64 边界、null、预算及超过种子文本上限的大主键。实现和新增测试为本仓库代码；Chinook 的固定版本和 MIT 许可保留在示例目录。
