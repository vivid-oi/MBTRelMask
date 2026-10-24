# 跨批稳定的整数映射

普通 `transform` 的编号依赖当前键集合。`transform_with_state(data, secret, previous=state, max_entries=100000)` 接受可选旧快照，返回 `MappedDataset`：`dataset()` 是完成结果，`state_json()` 是新快照。第一批不传 previous；同一策略和秘密下，之后已有键沿用原替换 ID，新键按确定的带秘密排序追加编号，消失的键不回收，重新出现时沿用旧值。text token 本身已是跨批确定的。

外键连通的列共享编号域；复合键仍按每个对应分量的域映射。数据必须在每一批中满足全部关系约束，状态不会补全缺失父行。首批同普通 transform 的结果相同，后续增量结果不保证与无状态 transform 相同。

```sh
# 设置同一个独立高熵 RELMASK_KEY，目标目录必须不存在。
moon run apps/relmask --target wasm -- export-state examples/chinook/policy.json examples/chinook/data.json - batch-1
moon run apps/relmask --target wasm -- export-state examples/chinook/policy.json examples/chinook/data.json batch-1/state.json batch-2
moon run apps/relmask --target wasm -- verify examples/chinook/policy.json batch-2/bundle.json
```

一次导出在同级私有暂存目录生成 `bundle.json` 和 `state.json`，检查完成且文件同步/关闭后才发布整个新目录。失败时两者都不作为最终目录发布，不覆盖旧目录和输入快照。普通错误清理暂存文件，强制终止、断电及共享目录边界见 [bundle 契约](bundles.md)。

状态采用 `relmask-state-1`。外层 body 字符串加完整 HMAC-SHA-256：对 JSON 字符串数组 `["relmask-state-auth-1", body]` 的 UTF-8 求 HMAC。body 绑定策略文本的精确指纹，包含按域和键摘要排序的分配表。键摘要为 `["relmask-state-key-1", policy_fingerprint, domain_number, normalized_integer_key]` 的完整 HMAC-SHA-256；不是原整数、原文本或秘密。认证后还检查域、键摘要格式、重复摘要、一一连续编号及 Int64 边界。跨批键相等依赖完整 HMAC 的抗碰撞假设，同批不同原键若摘要碰撞则拒绝。

默认和最高 100,000 个历史唯一整数键分配；可用 max_entries 设更小上限。所有域合计，删除数据不释放配额。输入状态文本还限制为 `max_entries * 160 + 100000` code units。超限、溢出、秘密不符、策略改变（含空白/换行）、损坏或未知字段拒绝；不会返回部分数据或新状态。旧快照字符串不被修改，修正输入后可重试。

必须串行使用最新快照并备份。没有并发合并、全局分配服务、跨分支唯一性或防回滚保证；同一旧快照分叉可能把同一新编号给不同键，不能自行拼接。状态透露关联和数量，应按敏感数据保管。秘密丢失无法继续，持有秘密者可重签状态；状态认证不为 bundle 提供签名，也不证明匿名化。实现沿用已有 HMAC，未经独立审计、不承诺常数时间或秘密擦除。

`moon run dev/state_workflow.mbtx -- wasm` 用完整 Chinook 加入一位新艺术家，检查原有 15,607 行替换值完全不变，以及目录配对发布、不覆盖、坏状态拒绝和恢复。单元测试另覆盖三十批追加、删除/重现、鉴别失败、策略不符、编号溢出和认证后畸形状态。
