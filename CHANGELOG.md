# Changelog

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循语义化版本。

## [0.3.0] - 2026-10-23

按第二轮评审意见（以 frePPLe 与 ERPNext MRP 为功能完整性参考）补齐计划内核缺口。

### Added

- SafetyStock::{Fixed, DaysOfDemand, PercentOfDemand}：安全库存可按固定值、需求天数或当期满需求百分比计算。
- Item.max_stock：库存上限，超过时逐期产生 StockException，对应 frePPLe 的 excess inventory 工作流。
- LotRule::ReorderPoint(level, quantity)：再订货点 + 再订货量规则（ERPNext 的 reorder level + reorder qty）。
- Item.phantom：虚拟件透传，不持有库存、不生成订单，需求在同一周期展开给子件。
- Plan.exceptions：库存过量异常清单；JSON 升为 moon-mrp.plan.v3。
- docs/capability.md：按 frePPLe features 与 ERPNext MRP 文档逐项对照的能力矩阵，含明确边界。
- 测试扩到 56 项/目标，新增安全库存策略、再订货点、虚拟件、过量异常与示例第 6 段。

### Changed

- Item.safety_stock: Qty 改为 Item.safety: SafetyStock；Item 增加 max_stock、phantom 字段。
- 安全库存改为逐期计算（safety(t)），其余净算顺序不变。
- README 增加能力矩阵链接、七类工作流与 0.3.0 迁移说明。
## [0.2.0] - 2026-10-22

针对首轮评审意见（功能范围偏窄、缺少小数用量/单位换算/损耗与良率/提前期异常处理/批量策略、规模上限过小）的重构版本。

### Added

- `Qty` 定点数量（3 位小数），工厂方法 `Qty::int` / `Qty::milli`，`to_string` 输出十进制文本；全流程 Int64 溢出检查与向上取整。
- `Item.yield_per_mille`：良率。订单按 `ceil(net * 1000 / yield)` 放大，`Bucket.received` 记录合格入库量。
- `Component.scrap_per_mille`：损耗。子件用量按 `(1 + scrap)` 放大后再乘单位用量。
- `Component.usage_unit` + `Request.conversions`：单位换算（例如 `G -> KG`），缺换算返回 `InvalidConversion` 而不是静默按 1:1。
- 批量政策扩展为六种：`LotForLot`、`FixedQuantity`、`Multiple`、`MinimumMultiple`、`PeriodOrder(n)`、`MinMax(min, max)`。
- `ReleasePolicy::{Strict, AllowLate}`：提前期不足时，可选择钳到第 0 期并在 `Plan.incidents` 记录、`Order.late` 标记。
- `Bucket.received`、`Order.late`、`Incident` 与新字段的 JSON 输出；schema 升为 `moon-mrp.plan.v2`。
- `docs/scenarios.md`：九组典型场景的对照数字与验证出处；`docs/semantics.md` 重写为 v2 语义。
- 测试扩到 49 项/目标，新增：小数用量、损耗、良率、换算、POQ、Min-Max、late 策略、独立模拟（324 组单层组合）、规模上限。

### Changed

- 规模上限：物料 64→4096、周期 128→1024、BOM 边 4096→100000、单据 10000→100000，提前期上限 4096。
- 数量上限保持 `10^12` 单位，但单位改为 milli-unit（最小 0.001）。
- 子件需求改为按父项投产数量（含良率放大）计算，损耗与换算逐步向上取整。
- README 增加六类工作流、0.1.0→0.2.0 迁移表与场景链接。

### Fixed

- 0.1.0 中提前期不足只能整体拒绝，无法表达"加急/晚下达"的业务选择。
- 0.1.0 的整数单位无法表达 2.5 KG 这类真实用量。

## [0.1.0] - 2026-10-20

首个可运行版本：无限产能假设下的离散周期多层物料需求计划。
