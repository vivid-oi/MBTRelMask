# 可复现的关系抽样

需要小型 CI 样本或复现包时，为目标表指定初始记录数和公开种子。工具按完整主键计算稳定排名，选择所需数量，再补齐关系依赖。这样无需维护手写主键清单，也不会因为导出文件行顺序改变而选中另一组记录。

## 完整示例

设置 README 中的 RELMASK_KEY 后：

```sh
moon run apps/relmask --target wasm -- export-sample examples/chinook/policy.json examples/chinook/data.json examples/chinook/sample.json chinook-demo-1 sample.bundle.json examples/chinook/select-options.json
moon run apps/relmask --target wasm -- verify examples/chinook/policy.json sample.bundle.json
```

sample.json 为 `{"Invoice":5}`。此固定数据和种子选择 5 张发票，select-options.json 沿明确的 InvoiceId 外键补齐全部 25 条明细及父依赖。省略 OPTIONS 时仍保留 5 张发票及父依赖，但不反向带入明细。SEED 为可公开的复现参数，替换字段所用的 RELMASK_KEY 仍通过环境变量传入。

命令形式为 `export-sample POLICY DATA REQUEST SEED DEST [OPTIONS]`。DEST 必须不存在，成功后生成复核所需的 bundle，stderr 为原有无原值转换报告。抽样或转换失败时不发布文件。

库入口：

```text
Plan::sample(source : String, request : String, seed : String,
             options? : String) -> String raise MaskError
```

request 是表名到非负整数数量的 JSON 对象，可同时指定多张表。先验证完整源数据；每张表选出指定数量的种子，合并这些种子后沿公共关系闭包引擎扩张。零数量合法，所有数量为零时所有表均为空。请求超过该表可用行数会拒绝，不自动减少数量；未知表、重复字段、空请求、负数、小数或字符串形式的数量都拒绝。

返回 JSON 仍含原值，分享前应调用 transform 或 transform_with_state。可先用 subset_where 形成有关系依赖的候选集，再对该候选集抽样；后续只能补齐候选集里实际存在的行。所有表、列和原始数字表示按原有契约保留，只有显式抽样排除的记录会移除。

## 稳定性与预算

- 排名材料为紧凑 JSON 字符串数组 `["relmask-sample-1", seed, table_name, canonical_primary_tuple]`，经 UTF-8 编码后计算完整 SHA-256，小排名优先。完整主键按现有 tuple_key 规则编码，整数先规范为 Int64 值。摘要相同则按完整键的 UTF-16 字典序打破平局。
- 排名不使用行位置、非主键值、表声明位置或策略指纹。相同主键集合与种子选出相同的初始种子集合；输出仍保留输入行顺序，因此重排行可改变输出文本。相同输入则输出完全确定。非主键更新不改变种子排名，但外键值或关系配置变化可能改变后续依赖闭包；增加或删除主键可能改变种子选择。
- 同一候选集与种子下，提高某表数量会保留该表原先选中的种子。不同种子可能得到不同选择，但不能保证必然不同。重复对结果使用相同请求和 options，结果幂等。
- 指定数量是种子数。自引用、父依赖或选定子表可使最终数量增加，不能承诺精确的最终总行数。options.max_rows 约束整个最终闭包；超限报错，不截断。
- 选择过程用最大堆保存每张表排名最小的 k 条候选，额外候选数至多 k；源数据本身仍按现有有界内存模型加载。没有流式输入、统计代表性、隐私或匿名化保证。

seed 要求 1–4096 UTF-16 code units，request 最多 1000000 code units。源数据、闭包和输出预算沿用 Plan / options。诊断包括 sample_seed_range、sample_request_too_large、empty_sample_request、sample_count_range、sample_population_too_small；类型、未知项、完整源数据和闭包错误沿用现有代码。错误位置不含种子或数据值。

## 验证

```sh
moon run dev/sample_workflow.mbtx -- wasm
```

脚本基于完整 Chinook 运行两次，检查输出逐字相同；倒序全部表后检查选中集合不变；独立核对 5 张发票、25 条明细和金额/日期/数量/引用，再验证已有文件不覆盖、可用记录不足和闭包预算拒绝、默认不含子表及失败恢复。为按原始 ID 独立核对公开数据，验证脚本临时将整数重编号规则设为 keep，保留联系方式替换；不修改仓库策略或原数据。README 的使用命令仍采用原策略。

堆测试用完整排序作为参照，覆盖容量 0–85、顺序变化、人工摘要碰撞及键字典序。库测试覆盖重排、数量递增、幂等、非主键更新、复合/布尔/Int64 键、循环、格式和预算。Native CI 配置也运行此文件流程；未推送提交的远端结果须等待相应 CI，不能以本机 Native 检查代替实际运行。
