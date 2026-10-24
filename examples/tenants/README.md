# 多租户事件导出

这是本项目编写的合成回归样本，随项目使用 Apache-2.0 许可。
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
