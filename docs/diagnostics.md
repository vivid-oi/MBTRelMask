# 一次定位多项导出问题

Plan::diagnose(data, max_issues=100) 返回不可变 Diagnostics：is_valid() 判断输入是否有效，to_json() 包含 valid、constraints_checked、truncated 和 issues。每条问题只有 code 和 location，没有原值、主键或映射。

先检查表/行/列结构及全部标量类型。存在此类问题时 constraints_checked 为 false，避免用缺字段或坏类型数据进行不可靠的引用判断。结构完整后检查全部主键、两种 UNIQUE null 语义和 SIMPLE/FULL 外键；同一批中可同时报告重复键、孤儿引用和部分 null。此时 constraints_checked 为 true，但只要有问题 valid 仍为 false。包含所有声明约束，不只检查首个错误。

max_issues 为 1–1000，默认 100。超过条数保留首批问题并置 truncated，不宣称列出全部问题数量。仍受策略输入大小/行数和解析深度限制；坏 JSON、重复对象字段或资源上限失败继续抛 MaskError，不返回不完整报告。已有 validate 仍保持遇错即停，转换前后的严格验证不被替换。

CLI 默认保留 100 条问题：

    moon run apps/relmask --target wasm -- diagnose examples/chinook/policy.json examples/chinook/data.json

有效输入返回 0，有问题返回 1，并把结构化报告写 stdout。解析或资源错误经原错误通道写 stderr。诊断不修复输入、不删行、不输出部分数据，也不保证后续转换一定成功，例如 token 长度、日期平移越界或转换后碰撞仍可能在转换阶段拒绝。

    moon run dev/audit_workflow.mbtx -- wasm

演练从完整 Chinook 构造临时错误副本，删除一个 Artist 并重复一个 Genre，验证同时发现重复键和孤儿 Album；再验证结构检查阶段、报告不含源值、有效输入的恢复。原数据不改动，Native CI 运行相同流程。
