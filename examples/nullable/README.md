# 每租户可空别名

这是随 Apache-2.0 发布的本项目合成约束样本。不同租户可各有一条 alias 为 null 的记录，但同一租户不能重复；将第二行 tenant 改为 north 会报 duplicate_key。可直接运行：

    moon run apps/relmask --target wasm -- check examples/nullable/policy.json examples/nullable/data.json

设置 RELMASK_KEY 后以 export 命令替换并导出，再 verify。完整元组而非 null 分量自身决定是否冲突；输入与输出两侧均验证。
