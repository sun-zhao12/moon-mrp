# 典型场景对照验证

本文件把 `moon-mrp` 的计算结果与成熟 MRP/ERP 的通用做法逐项对照，并给出可直接复算的数字。每个场景都指明由哪个测试或示例固定下来，避免文档与实现脱节。

## 1. 对照口径

| 能力 | 成熟方案中的常见做法 | 本库的实现与差异 |
| --- | --- | --- |
| 损耗（scrap） | 组件用量按 `(1 + scrap%)` 放大后取整 | `Component.scrap_per_mille`，先对父项投产数量放大再乘用量，逐级向上取整到 0.001 |
| 良率（yield） | 订单量 = 需求 / 良率，向上取整 | `Item.yield_per_mille`，`S = ceil(net * 1000 / yield)`，入库合格量 `floor(S * yield / 1000)`，保证 ≥ 净需求 |
| 单位换算 | BOM 行带用量单位，按换算表折算到基础单位 | `Component.usage_unit` + `Request.conversions`；缺换算直接报错，不按 1:1 猜测 |
| 批量政策 | L4L、FOQ、倍数、最小批量、POQ、Min-Max | 六种全部实现，见 `LotRule`；POQ 按窗口聚合，Min-Max 补到上限 |
| 安全库存 | 期末库存下限 | 每期 `needed = gross + safety`，不在每期重复计入需求 |
| 提前期不足 | 加急 / 推迟 / 拒绝并提示 | 默认 `Strict` 拒绝；`AllowLate` 钳到第 0 期并输出 `late` 与 `incident` |
| 可追溯 | 需求来源（peg） | `Peg` 区分独立需求与父项订单，合计等于周期毛需求 |
| 数值精度 | 十进制定点或高精度小数 | 定点 milli-unit（3 位小数），全流程 Int64 溢出检查 |

未在这些商业系统中实测，只是按其公开文档描述的通用算法对照；差异点已在上表列出。

## 2. 场景一：多层 BOM 与共享子件

输入：`KIT` 期初 1、提前期 1、倍数 5；`MODULE` 期初 4、提前期 2、倍数 4；`RAW` 期初 5、提前期 1。需求 `KIT` 第 5 期 9、`MODULE` 第 4 期 3；到货 `MODULE` 第 4 期 5。BOM：`KIT→MODULE` 2、`MODULE→RAW` 3、`KIT→RAW` 1。

期望与实测：

| 物料 | 订单 | 下达 | 收货 |
| --- | --- | --- | --- |
| KIT | 10 | 第 4 期 | 第 5 期 |
| MODULE | 16 | 第 2 期 | 第 4 期 |
| RAW | 43 | 第 1 期 | 第 2 期 |
| RAW | 10 | 第 3 期 | 第 4 期 |

验证：`core_test.mbt`「multilevel shared components are netted after every parent is exploded」，并逐期断言 Peg 合计等于毛需求。

## 3. 场景二：门店补货（最小批量 + 倍数 + 安全库存）

输入：`LABEL` 期初 3、安全库存 2、提前期 1、`MinimumMultiple(10, 4)`；第 1 期到货 2；需求第 2 期 9、第 3 期 3。

期望与实测：

| 期 | gross | scheduled | net | receipt | release | projected |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 0 | 0 | 0 | 0 | 0 | 3 |
| 1 | 0 | 2 | 0 | 0 | 12 | 5 |
| 2 | 9 | 0 | 6 | 12 | 0 | 8 |
| 3 | 3 | 0 | 0 | 0 | 0 | 5 |

验证：`examples/replenishment` 逐期断言库存守恒，`core_test.mbt` 另有 256 组日历的独立模拟对照。

## 4. 场景三：供应承诺变更

输入：`PART` 库存 2、提前期 1、需求第 3 期 8。初始计划补 6；供应商确认第 2 期到货 3 后用同一 API 重算，补货降为 3。

验证：`examples/demo` 第 3 段；输入对象不变，旧计划不被修改。

## 5. 场景四：良率、损耗、小数用量与单位换算

输入：`PANEL` 良率 95%；BOM 1 台用 2500 `G` 涂料，损耗 20%；`PAINT` 基础单位 `KG`，换算 `G→KG = 0.001`；需求 8 台于第 1 期。

期望与实测：

| 步骤 | 值 |
| --- | --- |
| 净需求 | 8 |
| 良率放大 | 8.422 |
| 损耗补偿 | 10.107 |
| 乘用量（G） | 25.2675 |
| 换算（KG，向上取整到 0.001） | **25.268** |

输出：PANEL 订单 8.422；PAINT 毛需求与订单 25.268 KG。

验证：`examples/demo` 第 4 段、`features_test.mbt`「yield inflates…」「scrap pads…」「unit conversion…」。

## 6. 场景五：期间订货量 POQ(3)

输入：`A` 无期初，需求第 1 期 10、第 2 期 5，批次政策 `PeriodOrder(3)`。

期望与实测：第 1 期一次下单 15；第 2 期不再下单；第 1 期结存 5，第 2 期结存 0。

验证：`features_test.mbt`「period order covers several buckets with a single order」。

## 7. 场景六：Min-Max(5, 20)

输入：`A` 期初 10，批次政策 `MinMax(5, 20)`，需求第 1 期 8。

期望与实测：`10 - 8 = 2 < 5`，补到 20，订单 18，期末结存 20。

验证：`features_test.mbt`「min-max replenishes up to the maximum」。

## 8. 场景七：提前期不足

输入：`PART` 库存 2、提前期 2、需求第 1 期 5。

- `Strict`：返回 `BeforeHorizon("PART", 1, -1)`，不返回部分计划。
- `AllowLate`：订单 3 在第 0 期下达，`late = true`，incident 记录 `required_release = -1`、`actual_release = 0`。

验证：`core_test.mbt`「early releases reject…」、`features_test.mbt`「late releases are clamped…」，以及 `examples/demo` 第 5 段。

## 9. 场景八：规模上限

| 维度 | 通过 | 拒绝 |
| --- | --- | --- |
| 物料 | 4096 | 4097 → `SizeLimit` |
| 周期 | 1024 | 1025 → `InvalidHorizon` |
| 需求单据 | 100000 | 100001 → `SizeLimit` |
| BOM 边 | — | 100001 → `SizeLimit`（先于重复检查） |

验证：`limits_test.mbt`。

## 10. 场景九：独立模拟对照

`features_test.mbt` 中的「single-level planning matches an independent simulation」对需求（0/1/3/7/12/30）× 期初（0/2/5）× 安全库存（0/1/4）× 良率（100%/90%/70%）× 倍数（1/5）共 324 组组合，用一份独立实现的库存递推逐期核对 `net`、订单数量、入库量与结存。这是与主实现的独立路径，不共享代码。
