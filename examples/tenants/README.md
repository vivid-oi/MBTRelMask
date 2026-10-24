# 多租户事件导出

这是本项目编写的合成回归样本，随项目使用 Apache-2.0 许可。

`full-policy.json` / `full-data.json` 演示 MATCH FULL：可空复合引用必须全部为空或全部有值。运行 `moon run apps/relmask --target wasm -- check examples/tenants/full-policy.json examples/tenants/full-data.json`，把第二条事件 account 从 null 改为 7 会被拒绝。
多个租户可拥有相同 account ID，因此只有 `(tenant, account)` 元组唯一。
事件引用完整元组；替换后仍可区分 north/7 与 south/7。

```sh
moon run apps/relmask --target wasm -- check examples/tenants/policy.json examples/tenants/data.json
# 设置 RELMASK_KEY 后运行：
moon run apps/relmask --target wasm -- mask examples/tenants/policy.json examples/tenants/data.json
```

第三条事件采用 MATCH SIMPLE：任意引用分量为 null 就不要求匹配父行。
非 null 分量仍执行自己的规则，原有 null 保留。
把第二条事件的 account 改为 8 会产生 `orphan_reference`；不能仅靠两个单列值分别存在来通过检查。

同一数据的 CSV 版本位于 `csv/`，以未加引号的 `\N` 表示 null。设置 RELMASK_KEY 后可运行：

```sh
moon run apps/relmask --target wasm -- export-csv examples/tenants/policy.json examples/tenants/csv tenants.bundle.json
moon run apps/relmask --target wasm -- unpack-csv examples/tenants/policy.json tenants.bundle.json tenants-csv
```
