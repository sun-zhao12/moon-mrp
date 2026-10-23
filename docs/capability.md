# 能力对照：frePPLe 与 ERPNext MRP

本文件按评审核验时给出的两份参考（2026-10-23 实际读取）：

- frePPLe Key features：<https://frepple.com/docs/current/features.html>
- ERPNext MRP 文档：<https://docs.frappe.io/erpnext/material-requirements-planning-mrp>

逐项比较"计划内核"能力，并标明本库实现程度与边界。**本库是库（计算内核），不是应用**：UI、数据库、REST 集成、多地点分配、有限产能排程属于应用层或优化层，不在库的职责内，但下表会把它们列出来，避免用"未提及"掩盖缺口。

## 1. 需求（Demand）

| 能力 | frePPLe | ERPNext MRP | moon-mrp |
| --- | --- | --- | --- |
| 按周期输入独立需求 | 有 | 有（销售订单/生产计划） | **有**：`Movement` 逐期输入 |
| 需求优先级 | 有（按优先级 + 交期排序） | 有（订单优先级） | 部分：需求按 ID 确定性排序；无限产能下不产生分配冲突，优先级不改变数量（见边界说明） |
| 统计预测（SES/DES/Holt-Winters/Croston） | 有 | 无（依赖销售预测单） | 不做：属需求计划模块，本库消费已确定的 `Movement` |
| 预测冲销（forecast consumption） | 有 | 不做 | 不做：同上 |

## 2. 库存与补货政策

| 能力 | frePPLe | ERPNext MRP | moon-mrp |
| --- | --- | --- | --- |
| 固定安全库存 | 有 | 有（Item safety stock） | **有**：`SafetyStock::Fixed` |
| 按需求天数/覆盖率的安全库存 | 有（qty 与 days-of-demand） | 有（按天数/百分比） | **有**：`DaysOfDemand(n)`、`PercentOfDemand(p)` |
| 最小/最大库存目标 | 有 | 有（reorder level） | **有**：`MinMax`、`Item.max_stock` |
| 再订货点 + 再订货量 | 有（reorder qty min/max） | 有（reorder level + qty） | **有**：`LotRule::ReorderPoint(level, quantity)` |
| 经济订货量（EOQ） | 有 | 无 | 不做：需要成本与持有率参数，属优化层 |
| 库存过量/缺货异常 | 有（excess/stockout 工作流） | 有（库存警示） | 部分：`Plan.exceptions` 报告过量；无限产能下不会出现"缺料"，缺口以 `late` 与 `incidents` 表达 |

## 3. BOM 与用量

| 能力 | frePPLe | ERPNext MRP | moon-mrp |
| --- | --- | --- | --- |
| 多层 BOM 展开 | 有 | 有 | **有** |
| 组件损耗（scrap %） | 有 | 有（BOM scrap） | **有**：`Component.scrap_per_mille` |
| 良率（yield） | 有 | 部分（按工序/物料损耗表达） | **有**：`Item.yield_per_mille` |
| 小数用量与单位换算 | 有（UOM） | 有（UOM conversion） | **有**：`Qty` 定点小数 + `usage_unit`/`conversions` |
| 虚拟件/Phantom | 有 | 有（子装配/虚拟件） | **有**：`Item.phantom` 透传展开 |
| 替代料、替代工艺、多版本 BOM | 有 | 部分（替代物料） | 不做：多来源分配属优化层，见第 6 节 |
| 联产品/副产品 | 有 | 有限 | 不做 |
| 工序、工作中心、路线 | 有 | 有 | 不做：本库只做物料计划 |

## 4. 计划引擎

| 能力 | frePPLe | ERPNext MRP | moon-mrp |
| --- | --- | --- | --- |
| 批量政策 | L4L、固定、POQ、min/max | 批量、最小/倍数 | **有六种**：L4L、FixedQuantity、Multiple、MinimumMultiple、PeriodOrder、MinMax、ReorderPoint |
| 提前期抵消 | 有 | 有 | **有**：按周期反推下达期 |
| 提前期不足的异常处理 | 有（加急/延后/迟到） | 有（计划延迟提示） | **有**：`Strict` 拒绝 / `AllowLate` 钳制并输出 incident |
| 安全库存为期末下限 | 有 | 有 | **有**（不重复计入需求） |
| 需求可追溯（pegging） | 有 | 有（MRP 明细） | **有**：独立需求 / 父项订单两类 Peg |
| 有限产能、排程、甘特图 | 有 | 有（工作站产能） | 不做：本库明确为无限产能物料计划 |
| 约束/非约束计划、DDMRP、优先级分配 | 有 | 部分 | 不做：见第 6 节 |

## 5. 输出与集成

| 能力 | frePPLe | ERPNext MRP | moon-mrp |
| --- | --- | --- | --- |
| 逐期毛/净需求、收货、下达、结存 | 有 | 有 | **有** |
| 订单/异常清单 | 有 | 有（物料请求/工单） | **有**：`orders`、`incidents`、`exceptions` |
| JSON 输出 | 有（REST） | 有（文档/报表） | **有**：`Plan::to_json`（plan.v3） |
| Web UI、权限、多语言 | 有 | 有 | 不做：库不带 UI |
| 与 ERP 的双向集成 | 有 | 本身是 ERP | 不做：库只提供纯函数与 JSON |

## 6. 明确边界

以下能力**没有实现**，原因不是"漏做"，而是属于不同层：

1. **有限产能与排程**：需要资源日历、工序、换型矩阵与约束求解；本库的定位是无限产能 MRP。
2. **多地点/分销网络（DRP、调拨、公平分配）**：需要库存按地点建模与网络分配算法。
3. **替代料/替代工艺的自动选择**：属于优化或约束求解，超出"确定性净算"范围。
4. **统计预测与预测冲销**：需求计划模块，本库接收已确认的需求。
5. **UI、数据库、REST 服务、ERP 集成**：库以纯函数 + JSON 交付，由宿主应用负责。

在这些边界之外，本库对"物料计划内核"的覆盖与两份参考一致：需求输入、BOM 展开（含损耗/良率/小数用量/单位换算/虚拟件）、库存与补货政策（固定/天数/百分比安全库存、再订货点、六种批量）、提前期与异常、可追溯输出。

## 7. 验证方式

- 每项能力都有对应测试（`*_test.mbt`），并写进 `docs/scenarios.md` 的对照表。
- 另有独立实现的单层模拟对 324 组组合逐期核对，见 `features_test.mbt`。
- 计划结果与手算数字的对照见 `docs/scenarios.md`，示例输出见 `docs/demo-output.txt`。
