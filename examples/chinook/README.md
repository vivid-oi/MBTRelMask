# Chinook

`data.json` 是上游原文件，未删行或抽样：

- 来源：https://github.com/lerocha/chinook-database
- 固定提交：`7f67772503d71ba90f19283c38e93923addb43fa`
- 原路径：`ChinookDatabase/DataSources/ChinookData.json`
- SHA-256：`2998161de437518e3447e779c7ce7418f081895e388081bff315f3c258752d8c`
- MIT 许可文本保留在同目录 `LICENSE.md`。

媒体资料来自原作者的 iTunes 库；客户、员工和销售资料是上游构造的测试数据。这不是生产数据，也不能用本示例证明真实个人信息已经匿名。

`policy.json` 使用全部 11 张表和公开关系模型，包括员工自引用和 PlaylistTrack 复合主键。可用 `moon run dev/chinook_policy.mbtx` 重建，再审阅明确的列策略。

演示修改 ID 与引用、客户/员工联系信息、账单地址；保留交易时间、金额、曲目和数量。它展示关系与保真性，不代表这些保留字段在所有真实场景中都不敏感。

`moon run dev/verify.mbtx -- native` 真正调用 CLI，逐表比较行/列数量、金额和时间，并独立遍历客户→发票→明细引用。

select-2022.json 与 select-options.json 是本仓库编写的条件/关系配置，选择 2022 年的 83 张发票、455 条明细及父依赖。运行方法见[条件选样](../../docs/selection.md)，自动验证为 dev/selection_workflow.mbtx；不改动上游 data.json。

select-high-total.json 选择 Total >= 20.00 的 4 张发票；配合 select-options.json 保留全部 56 条明细。自动验证以整数分独立计算期望集合，金额筛选不使用 Double，输出保留原始数字表示。新增配置和验证代码使用本仓库 Apache-2.0 许可。

sample.json 指定抽取 5 张发票；公开种子 chinook-demo-1 配合 select-options.json 得到全部 25 条明细及父依赖。命令及稳定性边界见[关系抽样](../../docs/sampling.md)，自动验证为 dev/sample_workflow.mbtx。新增配置与代码使用仓库 Apache-2.0 许可，原始数据与 MIT 许可不变。
