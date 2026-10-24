# MBTRelMask

把现有多表 JSON / CSV 数据变成仍可联表使用的测试数据：关联键一起替换，未指定修改的值保留，主键、外键和唯一约束在转换前后都检查。

适合已经导出的故障复现包和 CI 样本。输入是数据和显式策略，不连接数据库，不扫描猜测哪些字段敏感。

## 跑一个完整例子

需要当前稳定版 MoonBit。文件命令支持 Native 和 moonrun 的 Wasm 宿主；核心库另支持 Wasm-GC 和 JavaScript。Native 还需系统 C 工具链；Windows 使用带 C++ 工具和 Windows SDK 的 MSVC 开发者终端。没有 C 编译器时，将下面命令的 `--target native` 改为 `--target wasm`。

```sh
moon update
moon run apps/relmask --target native -- check examples/chinook/policy.json examples/chinook/data.json
```

Linux / macOS：

```sh
export RELMASK_KEY='public-example-key-never-use-for-private-data'
moon run apps/relmask --target native -- export examples/chinook/policy.json examples/chinook/data.json sample.bundle.json
```

PowerShell：

```powershell
$env:RELMASK_KEY = 'public-example-key-never-use-for-private-data'
moon run apps/relmask --target native -- export examples/chinook/policy.json examples/chinook/data.json sample.bundle.json
```

`export` 将替换后的数据、无原值报告、策略指纹和完整性摘要写成一个文件。目标必须不存在；同目录私有临时文件写入、同步、关闭后再发布，普通失败会清理临时文件。已有文件不会被覆盖。

接收方保留原策略文件，无需原数据和秘密即可复核：

```sh
moon run apps/relmask --target native -- verify examples/chinook/policy.json sample.bundle.json
```

需要纯数据时，`mask POLICY DATA` 在整个数据集验证成功后才向 stdout 写 JSON，报告写入 stderr。退出码：0 成功、1 数据/策略/I/O 错误、2 用法错误。`mask` 的 shell 重定向可能提前截断目标文件；持久导出推荐使用 `export`。

Chinook 示例保留全部 11 张表，重编号关联整数 ID，替换客户/员工联系方式，保留金额和交易时间。原数据中的个人信息本来就是虚构样本。来源、固定版本和校验和见 [示例说明](examples/chinook/README.md)。

## 策略

```json
{
  "tables": [{
    "name": "users",
    "columns": [
      {"name": "id", "type": "integer", "rule": {"reindex": 1000}},
      {"name": "email", "type": "text", "rule": {
        "token": {"domain": "email", "suffix": "@example.test"}
      }}
    ],
    "primary": ["id"],
    "unique": [["email"]]
  }]
}
```

每列都要选择 `keep`、`null`、`replace`、`token` 或 `reindex`。相互引用的列必须使用相同规则；具体格式及错误语义见 [数据契约](docs/contract.md)。

库入口为 `vivid-oi/relmask/relmask`：`Plan::parse`、`Plan::validate`、`Plan::subset`、`Plan::transform`、`Plan::verify_bundle`，以及多表 `import_csv` / `export_csv`；完成结果提供 `to_json`、`report_json`、`bundle_json`。[库示例](relmask/README.mbt.md)参与编译与测试。

## 当前边界

- 支持单列和复合外键、自引用、单列及复合主键/唯一约束；复合外键按完整元组检查，采用 MATCH SIMPLE。
- 文本、Int64、布尔、null，以及不参与键运算的十进制数。数字原始表示保留，大整数不经 Double 比较。
- JSON 重复字段、未知表列、缺失字段、孤儿引用、输出碰撞、超长文本、整数溢出和不支持的配置均拒绝。
- 只处理有界内存数据；默认总行数 100,000，输入 16,000,000 个 UTF-16 code units。CLI 另有硬字节上限。
- 字符串使用精确相等，不模拟数据库排序规则、触发器或任意业务 CHECK。不保证任意业务查询行为相同。

`token` 是带秘密的 HMAC-SHA-256，使用 128-bit token 并在当前数据集中检查碰撞。`reindex` 是当前批次内的一一重编号；输入键集合改变后映射可能改变。

这是假名化，不是匿名化。相等关系、频率和关系图仍然可见；没有自动 PII 检测、隐私合规或不可重识别承诺。密码实现有标准向量测试，未经独立安全审计，也不承诺常数时间或秘密内存擦除。私有数据请使用独立的高熵秘密，不要使用公开示例密钥。

## 验证

```sh
moon fmt --check
moon info
moon check --target wasm-gc --deny-warn
moon test --target wasm-gc --deny-warn
moon run dev/verify.mbtx -- native
```

CI 在三个可移植后端运行核心测试，在 Linux、macOS、Windows 真正运行 Native 命令和 Chinook 工作流。

多租户场景见[复合引用示例](examples/tenants/README.md)。

需要缩小故障样本时，`Plan::subset` 和 `export-subset POLICY DATA SEEDS DEST` 会保留指定记录及递归父依赖，然后可以继续替换和复核。见[关系裁剪](docs/subsets.md)。

需要保留完整订单/发票时，可用 `export-aggregate POLICY DATA SEEDS OPTIONS DEST` 指定反向扩张的子表和总行数上限；超限拒绝，不截断。

已有 CSV 导出时，`export-csv POLICY DIRECTORY DEST` 按目录清单读取全部表，验证关系并替换后生成 bundle；`unpack-csv POLICY BUNDLE DESTDIR` 复核后输出 CSV 文件和清单。保留精确数字、null 和空文本，支持多行字段。见 [CSV 契约与示例](docs/csv.md)。

三套采用流程见[使用场景](docs/workflows.md)，文件格式和失败恢复见[导出契约](docs/bundles.md)。完整性摘要没有秘密，不能认证发布者；修改策略空白或换行也会改变指纹。文件中的变更数量无法在缺少原数据时独立证明。

后续按实际采用需求推进跨批持久映射；该能力尚未实现。现有 CSV 只支持文档明确列出的方言和 null 约定。

Apache-2.0。外部资源及许可见 [THIRD_PARTY.md](THIRD_PARTY.md)。
