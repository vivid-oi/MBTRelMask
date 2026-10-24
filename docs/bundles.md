# 可复核的文件产物

`export POLICY DATA DEST` 在内存中完成转换和所有约束检查，再生成单文件 bundle；不把原数据、秘密或映射表加入 bundle。

```sh
# 预先设置 RELMASK_KEY；不要在私有数据上使用公开示例密钥。
moon run apps/relmask --target wasm -- export examples/chinook/policy.json examples/chinook/data.json sample.bundle.json
moon run apps/relmask --target wasm -- verify examples/chinook/policy.json sample.bundle.json
```

文件为严格 JSON 对象，五个必需字段均为字符串：

| 字段 | 内容 |
| --- | --- |
| format | `relmask-bundle-1` |
| policy_sha256 | 原策略字符串 UTF-8 的完整 SHA-256，包含空白与换行 |
| data | 规范化后的数据 JSON 文本；数字原始表示保持 |
| report | 无原值报告的规范 JSON 文本 |
| sha256 | 下述有边界编码的完整摘要 |

摘要计算对紧凑 JSON 字符串数组 `["relmask-bundle-1", policy_sha256, data, report]` 的 UTF-8 求 SHA-256。将内层 JSON 保存为字符串是为了让数值原始表示和摘要的字节边界清晰，不能把它替换为嵌套对象。

`Plan::verify_bundle` 验证格式、未知/重复字段、摘要、原策略指纹，然后重新检查类型、完整键元组、唯一性及引用；验证数据规范表示、报告表名/顺序/行数/算法、变更数量的范围。成功返回 `CheckedDataset`，可取出 `to_json()` 交给下游导入器；`bundle_json()` 往返保持相同内容。转换后的数据仍受策略输入大小限制，扩张过量返回 `output_too_large`。

摘要可以被修改文件的人重新计算，因此不是签名。验证不能证明生产者用了某个秘密、原值全部移除、变更数量真实或数据匿名。变更数量只做范围检查；确切变更数需要原数据。接受样本前仍应审查策略中的 keep 列及应用特有的隐私要求。

## 写入和恢复

临时文件在目标同一目录，以随机名称和 `.pending` 结尾，独占创建；POSIX 权限请求为 0600，Windows 使用系统 ACL。写入并同步文件、关闭句柄后，使用不替换已有目标的重命名发布。Linux、macOS、Windows 的运行路径由 CI 验证，实际文件系统必须支持相应操作；不支持时报告 I/O 错误，不退化为覆盖写入。未创建父目录，不跟随已有目标来覆盖文件。

普通写入或发布失败时删除该次临时文件；清理也失败会输出 `cleanup_failed` 及待清理路径。进程被强制终止时可能遗留临时文件；确认无运行中的导出后可手动删除。没有目录同步、断电持久性、网络文件系统或敌对共享目录保证。不要把目标放在不可信用户可替换目录项的位置。

CLI 的 bundle 上限为 128 MB；策略 4 MB、原数据 64 MB。库另使用有界输入和报告开销预算。格式、摘要、策略不匹配均返回带位置的 `MaskError`，不输出部分数据。

```sh
moon run dev/bundle_workflow.mbtx -- wasm
```

该自动化用完整 Chinook 数据验证导出、无需秘密的复核、已有文件不变、坏数据不发布、目录目标失败、临时文件清理及出错后恢复。它在随机临时目录内运行，不覆盖工作目录文件。
