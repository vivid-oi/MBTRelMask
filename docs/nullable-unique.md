# 可空唯一键

数组形式保持既有 NULLS DISTINCT 行为。唯一约束也可以写为：

    {"columns":["tenant","alias"],"nulls":"not_distinct"}

NULLS NOT DISTINCT 将 null 视为相等分量，按完整元组判重：不同 tenant 的 null alias 不冲突，同一 tenant 的两条 null alias 冲突。对象可显式设 nulls 为 distinct，省略也采用原默认；其他模式和未知字段拒绝。

主键仍拒绝 null。外键 SIMPLE/FULL 规则不受影响，目标仍必须是声明的主键或唯一键。输入、转换后、CSV、bundle、子集与比较统一检查；转换将多条值清空而导致冲突时也会拒绝，不静默删行。

语义参考 [PostgreSQL 唯一约束](https://www.postgresql.org/docs/current/ddl-constraints.html#DDL-CONSTRAINTS-UNIQUE)，不是对所有数据库排序和 null 规则的模拟。可运行样本见 [每租户别名](../examples/nullable/README.md)，样本与测试均由本项目构造，随 Apache-2.0 发布。
