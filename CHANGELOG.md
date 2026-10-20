# Changelog

格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循语义化版本。

## [0.1.0] - 2026-10-20

首个可运行版本：无限产能假设下的离散周期多层物料需求计划。

### Added

- `plan(Request) -> Result[Plan, PlanningError]`：全量输入校验、父项优先的确定性拓扑净算、共享子件合并、逐期毛/净需求与计划订单。
- `order_quantity(net, LotRule) -> Result[Int64, PlanningError]`：`LotForLot`、`Multiple(m)`、`MinimumMultiple(min, m)` 三种批量政策，可脱离 BOM 单独调用。
- `Plan::to_json`：`moon-mrp.plan.v1` 结构，数量一律为十进制字符串，避免 JS 数值精度损失。
- `Peg`：`Demand(id)` 与 `ParentOrder(sku, receipt_bucket)` 两种需求来源，合计等于对应周期的毛需求。
- `examples/demo`：装配与共享子件、门店补货、供应承诺变更三条工作流，另演示提前期不足与 BOM 成环被拒绝。
- `examples/replenishment`：单店补货示例，逐期打印计划表并按独立递推断言库存守恒。
- 测试覆盖：共享子件净算、现货与到货抵扣、安全库存、提前期反推、图验证、输入顺序、整数上限、JSON 字段、批量政策边界、UTF-16 排序、重复计算确定性、文档化规模上限；每目标 34 项具名测试。
- `docs/semantics.md`：逐期公式、完整数字示例、错误表与上限表。
- GitHub Actions：`moon check`、`moon build`、`moon test` 覆盖 wasm / wasm-gc / js / native，并运行两个示例。

### Changed

- 周期、期号、提前期与索引使用 `Int`，数量使用 `Int64`；`Int` 在 0.10.14 与 0.10.16 两代工具链上都能编译。
- CI 不以格式化结果作为门禁：两代格式化器对 `Int` 与可选参数记号的规范化不同，同一份源码无法同时满足。
- 模块名由 `fan-ere/moon-mrp` 改为 `sun-zhao12/moon-mrp`，与发布账号和仓库所有者一致。

### Notes

- 不处理有限产能、供应商实际可交付性、替代料、损耗率、小数单位、保质期、成本优化、采购事务或跨批次状态。
- 项目申报书只保留在本地，不进入仓库、Release 或发布包。
