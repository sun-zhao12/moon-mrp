# 计划语义与示例

本文件说明 `plan` 的计算顺序、字段定义、批量政策、损耗/良率/单位换算规则、拒绝条件与规模上限。内容与 `types.mbt`、`quantity.mbt`、`planning.mbt`、`export.mbt` 及测试一致。

## 1. 数量表示

所有数量使用定点小数 `Qty`：`1000` 个 milli-unit 为 1 个单位，最小步长 `0.001`，不使用二进制浮点。

- `Qty::int(2)` = `2`，`Qty::milli(250)` = `0.25`。
- 工厂方法、`add/sub/compare/to_string` 都在 `quantity.mbt`。
- 数量一律非负，上限 `10^12` 个单位（即 `10^15` milli-unit）；超限返回 `QuantityLimit`，不截断、不饱和。
- 每级乘法先做溢出检查，再向上取整到 `0.001`（见第 3、4 节）。

## 2. 记号

| 记号 | 含义 |
| --- | --- |
| `t` | 周期序号 `0..horizon-1`，不隐含天、周、时区 |
| `projected[t]` | 第 `t` 期期末预计结存；`projected[-1]` 取 `Item.on_hand` |
| `scheduled[t]` | 第 `t` 期已排定到货 |
| `gross[t]` | 第 `t` 期毛需求（独立需求 + 父项计划订单贡献） |
| `net[t]` | 第 `t` 期净需求（良品单位） |
| `S_t` | 第 `t` 期订单的投产数量（含良率补偿与批量取整） |
| `received_t` | 第 `t` 期该订单的合格入库量 |
| `receipt/release` | 计划收货 / 计划下达 |

## 3. 逐期净算顺序

对每个物料按拓扑序（父项先于子项）：

1. `available = projected[t-1] + scheduled[t]`（到货只在所属期可用）
2. `needed = gross[t] + safety(t)`（按第 12 节的策略计算，安全库存是期末下限，不重复计入需求）
3. `net[t] = max(0, needed - available)`
4. 求订单投产数量 `S_t`（第 4 节：批量政策、良率、损耗、单位换算）
5. `received_t = floor(S_t * yield / 1000)`
6. `projected[t] = available + received_t - gross[t]`
7. `release = t - lead_time`（第 6 节：不足时的两种策略）

**子件需求只由计划订单产生**：`child.gross[release] += ceil(S_t * ...)`。现货与已排定到货不会再次展开成子件需求。

## 4. 批量政策与订单数量

| 政策 | `order_quantity(net, lot)` 与计划内实际行为 |
| --- | --- |
| `LotForLot` | 订单等于净需求 |
| `FixedQuantity(q)` | 按 `q` 的整批次取整（向上） |
| `Multiple(m)` | 向上取到 `m` 的整数倍 |
| `MinimumMultiple(min, m)` | 先满足 `min`，再向上取到 `m` 的倍数 |
| `PeriodOrder(n)` | 一次订单覆盖 `t..t+n-1` 的净需求；`order_quantity` 无法预知日历，因此返回净需求本身 |
| `MinMax(min, max)` | 当 `available - gross[t] < min` 时补到 `max`；`order_quantity` 返回 `max(net, max)` |
| `ReorderPoint(level, quantity)` | 当 `available - gross[t] < level` 时下单 `max(net, quantity)`；`order_quantity` 返回 `max(net, quantity)` |

计划内的 `S_t` 计算顺序是：**先按良率放大，再按批量政策取整**（`PeriodOrder`/`MinMax` 自身已完成批量聚合，不再叠加取整）。

对 `PeriodOrder(n)`，窗口需求为：

```
required = 0
projected = available
for k = t .. min(t+n-1, horizon-1):
    projected += scheduled[k] - gross[k]
    if projected < safety:
        required += safety - projected
        projected = safety
```

## 5. 损耗、良率与单位换算

- **良率 `Item.yield_per_mille`**（`1..1000`）：订单只有该比例的合格品入库。`S_t = ceil(net * 1000 / yield)`，`received = floor(S * yield / 1000)`，因此 `received >= net`。
- **损耗 `Component.scrap_per_mille`**（`0..1000`）：每个父项订单要为子件多备 `scrap` 比例的用量。计算时先对 `S_t` 做 `ceil(S * (1000 + scrap) / 1000)`，再乘单位用量。
- **单位换算**：`Component.usage_unit` 为空或等于子件 `Item.unit` 时直接使用 `units_per`；否则必须在 `Request.conversions` 中提供 `from -> to` 的换算因子（例如 `G -> KG` 为 `0.001`），缺失时报 `InvalidConversion`，不会静默按 1 处理。
- 三步（损耗、用量、换算）各自 `ceil` 到 `0.001`，因此结果只会偏大，不会少备料。

## 6. 提前期不足

- `ReleasePolicy::Strict`（默认）：任一下达早于第 0 期即返回 `BeforeHorizon`，整次计算失败，不返回部分计划。
- `ReleasePolicy::AllowLate`：下达期钳到第 0 期，`Order.late = true`，并在 `Plan.incidents` 中记录 `{item, receipt_bucket, required_release, actual_release}`，供计划员判断是否加急。

## 7. 需求贡献（Peg）

`Peg` 记录毛需求来源：`Demand(id)`（独立需求）或 `ParentOrder(sku, receipt_bucket)`（父项订单）。同一物料同一周期的 Peg 合等于该周期 `gross`。Peg 不是批次分配证明，也不承担安全库存分摊。

## 8. 完整示例：良率 + 损耗 + 小数用量 + 单位换算

输入（`examples/demo` 第 4 段）：

- `PANEL`：良率 95%，提前期 0；需求 8 台于第 1 期
- `PAINT`：单位为 `KG`
- BOM：1 台 PANEL 用 2500 `G` 涂料（=2.5 KG），损耗 20%
- 换算：`G -> KG` 因子 `0.001`

计算：

| 步骤 | 值 |
| --- | --- |
| 净需求 | `8` |
| 良率放大 | `ceil(8 * 1000 / 950) = 8.422` |
| 损耗补偿 | `ceil(8.422 * 1200 / 1000) = 10.107`（以 PANEL 计） |
| 乘用量 | `ceil(10.107 * 2500 / 1000) = 25.2675`（G 的 milli 表示） |
| 单位换算 | `ceil(25.2675 * 0.001) = 25.268`（KG，向上取到 0.001） |

输出：PANEL 订单 8.422（第 1 期下达与收货）；PAINT 毛需求 25.268 KG、订单 25.268 KG。

## 9. 拒绝条件

任何检查失败都返回 `Err`，不返回部分计划，不修改调用方数组。

| 错误 | 触发条件 |
| --- | --- |
| `InvalidHorizon` | `horizon < 1` 或 `> 1024` |
| `SizeLimit` | 物料 0 或 >4096、BOM 边 >100000、需求或到货 >100000 |
| `InvalidItem` | SKU 为空、数量越界、提前期不在 `0..4096`、良率不在 `1..1000`、批量政策非法、安全库存策略非法、虚拟件带库存/安全库存/上限/到货 |
| `DuplicateItem` | 同一 SKU 两次 |
| `UnknownItem` | BOM 或单据引用不存在的物料 |
| `InvalidComponent` | 父子相同、`units_per <= 0`、损耗不在 `0..1000` |
| `DuplicateComponent` | 同一父子边重复 |
| `InvalidConversion` | 换算单位为空/相同、因子非正，或缺失所需换算 |
| `InvalidMovement` | ID 为空或重复、周期越界、数量 `<= 0` 或越界 |
| `DuplicateMovement` | 同一集合内 `id` 重复 |
| `Cycle` | 拓扑排序仍有未访问节点（列表含环的下游节点） |
| `QuantityLimit` | 聚合、`gross+safety`、`available`、批量取整或结存超过 `10^12` 单位，或乘法会溢出 |
| `BeforeHorizon` | `Strict` 策略下某订单需在第 0 期之前下达 |

## 10. 输出、排序与确定性

- 物料按 SKU 的 UTF-16 字典序；订单按 SKU、收货期；Peg 按 SKU、周期、来源（独立需求先于父项订单）；incidents 按 SKU、收货期。
- 输入行顺序不影响结果；`plan` 复制输入数组后排序，不修改调用方数据。
- 同一输入重复调用结果相同；`Plan`、`ItemPlan`、`Bucket`、`Order`、`Peg`、`Incident`、`PlanningError` 都实现 `Eq` 与 `Debug`。
- `Plan::to_json` 输出 `moon-mrp.plan.v3`：数量为十进制字符串（如 `"0.25"`、`"25.268"`），订单带 `late` 布尔，`incidents` 与 `exceptions` 为数组。

## 11. 规模上限

| 维度 | 上限 | 说明 |
| --- | --- | --- |
| 物料 | 4096 | 索引与拓扑均按 SKU 确定性排序 |
| 周期 | 1024 | 每物料每期一个 `Bucket` |
| BOM 边 | 100000 | 重复边仍按 `DuplicateComponent` 拒绝 |
| 需求 / 到货 | 各 100000 | ID 分别在各自集合内唯一 |
| 提前期 | 4096 | 超出周期范围时按策略报错或钳制 |
| 数量 | `10^12` 单位 | 全部中间值受 Int64 溢出检查保护 |
## 12. 安全库存策略

Item.safety 决定每期期末下限：

| 策略 | 计算 |
| --- | --- |
| Fixed(q) | 每期固定 q |
| DaysOfDemand(n) | 全周期平均毛需求 × 
（向上取整），
 为周期数 |
| PercentOfDemand(p) | 当毛需求 × p%（向上取整），p 取  ..100 |

安全库存仍是期末下限：
eeded = gross + safety(t)，不会逐期累加。DaysOfDemand 用整个 horizon 的平均需求，而不是滚动历史（本库无历史窗口）。

## 13. 虚拟件（phantom）

Item.phantom = true 表示透传件：不持有库存、不生成订单、不做批量。

- 它的毛需求在同一周期按 BOM 直接展开给子件（沿用损耗、用量与换算规则）。
- 虚拟件自身仍输出逐期 Bucket，但 
et/receipt/received/release/projected 恒为 0。
- 为保证语义自洽，虚拟件不允许带期初库存、安全库存、上限或到货，违反时返回 InvalidItem。

## 14. 库存异常

Plan.exceptions 报告超过 Item.max_stock 的期末结存：

`
{ item, bucket, projected, maximum }
`

max_stock = 0 表示不启用该检查。无限产能模型下不会出现"缺料"，物料不足表现为 late 订单与 Plan.incidents，不写进 exceptions，避免把两类问题混在一起。
