# 合并关系样本

两位开发者从同一数据源截取复现数据时，经常带上相同客户、商品或组织记录。直接拼接会产生重复主键；分别重编号又可能让相同 ID 指向不同原记录。这里先对原始导出做严格集合合并，再统一转换。

两个输入必须属于同一逻辑数据源、同一主键命名空间和同一策略；各自必须是完整、有效的关系数据集。工具无法证明数据来源相同。不要把不同数据库、不同秘密或独立重编号的输出交给此接口；数值 ID 恰好相同不能证明它们代表同一实体。

## 使用

```text
Plan::merge_datasets(left : String, right : String) -> MergedDataset raise MaskError
MergedDataset::to_json() -> String
MergedDataset::report_json() -> String
```

to_json 仍含原值，应再传入 Plan.transform 或 transform_with_state。report_json 返回 relmask-merge-1 格式、按策略表顺序排列的 left、right、reused、added、result 数量，不含主键、原值或映射。

设置 README 中的 RELMASK_KEY 后，CLI 可直接合并并替换为 bundle：

```sh
moon run apps/relmask --target wasm -- export-merged POLICY LEFT_DATA RIGHT_DATA DEST
moon run apps/relmask --target wasm -- verify POLICY DEST
```

DEST 必须不存在。成功时 stderr 输出一个包含 merge 与 transform 两份报告的 JSON 对象。任何输入、合并或转换失败均不发布文件。

## 确定性与拒绝条件

- 使用完整主键匹配，复合键保持分量边界，Int64 不经 Double。
- 保留左侧行顺序，再追加右侧首次出现的记录。同主键记录须全部单元格相同；只复用完全相同的记录，不选择“较新”值，不自动修补。报告明确计数复用行为。
- 忽略对象字段顺序及 JSON 转义拼写差别；数字原始表示逐格比较。即使数值相等，1e400 与 1E400 或 -0 与 0 的冲突也拒绝，避免静默丢失原始表示。
- 两侧分别检查全部约束，然后检查合并后的约束。不同主键可能新产生唯一键冲突；不能以另一侧的父行掩盖本来无效的孤儿输入。
- 每侧都受 Plan 的输入/行数预算约束。合并结果另受总行数及完整输出预算约束；不会截断。无冲突时，合并幂等；交换输入保持相同记录集合，但可能改变行顺序。

同主键内容不同返回 merge_row_conflict，位置为右侧表名和行索引，不带主键或冲突值；结果行数超限返回 merge_row_limit，编码超限返回 output_too_large。其他错误沿用数据契约。失败不修改 Plan，不返回部分结果。

## 真实数据验证

```sh
moon run dev/merge_workflow.mbtx -- wasm
```

脚本在临时目录基于公开 Chinook 完整数据增加一名 Artist，再与原数据合并。核对复用 15607 行、增加 1 行；统一转换结果与直接转换右侧完整数据相同，并验证 bundle、目标不覆盖、冲突不发布和再次调用恢复。该脚本也加入 Native 的 CI 工作流。Chinook 来源及 MIT 许可见 examples/chinook/README.md；合并代码和新增探针按本仓库 Apache-2.0 提供，无外部实现或测试代码复用。
