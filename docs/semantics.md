# 计划语义与示例

本文件说明 `plan` 的实际计算顺序、每个字段的定义、拒绝条件与输入上限。所有内容与 `types.mbt`、`planning.mbt`、`export.mbt` 及测试保持一致；数字例子可直接用 `moon run examples/replenishment` 复现。

## 1. 记号

| 记号 | 含义 |
| --- | --- |
| `t` | 周期序号，取值 `0..horizon-1`，不隐含天、周、时区或工作日 |
| `projected[t]` | 第 `t` 期期末预计结存；`projected[-1]` 取 `Item.on_hand` |
| `scheduled[t]` | 第 `t` 期已排定到货（`Request.receipts` 按周期聚合） |
| `gross[t]` | 第 `t` 期毛需求，由独立需求与父项计划订单共同贡献 |
| `net[t]` | 第 `t` 期净需求 |
| `receipt[t]` | 第 `t` 期计划收货 |
| `release[t]` | 第 `t` 期计划下达，等于第 `t + lead_time` 期的计划收货 |

## 2. 逐期净算顺序

对每个物料、按其拓扑序（父项先于子项）执行：

1. `available = projected[t-1] + scheduled[t]`（到货只能在所属期使用，不向前借用）
2. `needed = gross[t] + safety_stock`（安全库存是每期期末下限，不是每期重复加入的需求）
3. `net[t] = max(0, needed - available)`
4. `receipt[t] = lot_round(net[t])`，净需求为 0 时不发单，即便存在最小订购量
5. `projected[t] = available + receipt[t] - gross[t]`
6. `release[t - lead_time] = receipt[t]`；若 `t - lead_time < 0`，本次计算整体失败

**子件需求只由计划下达产生**：`child.gross[release] += receipt * units_per`。现货与已排定到货不重复展开成子件需求，这也是"成品库存可以吃掉父项计划"的原因。

## 3. 批量政策

| 政策 | 规则 |
| --- | --- |
| `LotForLot` | 计划收货等于净需求 |
| `Multiple(m)` | 向上取到 `m` 的整数倍 |
| `MinimumMultiple(min, m)` | 先满足 `min`，再向上取到 `m` 的整数倍 |

`minimum` 与 `m` 都在 `1..10^9`；`Multiple` 的第二个分量不存在，`MinimumMultiple` 两个分量都必须合法。舍入结果超过 `10^12` 时返回 `QuantityLimit("lot rounding")`，不截断、不饱和。

## 4. 需求贡献（Peg）

`Peg` 记录某个物料某个周期毛需求的来源：

- `Demand(id)`：来自独立需求，`id` 即 `Request.demands` 中的 `Movement.id`
- `ParentOrder(sku, receipt_bucket)`：来自父项在某期收货的计划订单

同一物料同一周期的所有 `Peg.quantity` 之和等于该周期的 `gross`。`Peg` 不是现货批次分配证明，也不承担安全库存分摊。

## 5. 完整示例

`examples/replenishment` 的输入：`LABEL` 期初 3、安全库存 2、提前期 1、`MinimumMultiple(10, 4)`；周期 0..5；需求 `store-a` 第 2 期 9、`store-b` 第 3 期 3；到货 `open-po` 第 1 期 2。

| t | gross | scheduled | net | receipt | release | projected |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 0 | 0 | 0 | 0 | 0 | 3 |
| 1 | 0 | 2 | 0 | 0 | 12 | 5 |
| 2 | 9 | 0 | 6 | 12 | 0 | 8 |
| 3 | 3 | 0 | 0 | 0 | 0 | 5 |
| 4 | 0 | 0 | 0 | 0 | 0 | 5 |
| 5 | 0 | 0 | 0 | 0 | 0 | 5 |

第 2 期 `net = 9 + 2 - 5 = 6`，`MinimumMultiple(10,4)` 向上取到 12；提前期 1 期，因此 12 单位在第 1 期下达。第 3 期结存 8，覆盖 3 单位需求与 2 单位安全库存后仍有 5 剩余，不再发单。

对应订单与 Peg：

- 订单：`LABEL quantity=12 receipt=2 release=1`
- Peg：`Demand("store-a")` 贡献第 2 期 9；`Demand("store-b")` 贡献第 3 期 3
- JSON：`{"schema":"moon-mrp.plan.v1","horizon":6,...}`，数量一律是十进制字符串

## 6. 拒绝条件

任何一项检查失败都会让整次计算返回 `Err`，不返回部分计划，也不修改调用方数组。

| 错误 | 触发条件 |
| --- | --- |
| `InvalidHorizon` | `horizon < 1` 或 `> 128` |
| `SizeLimit` | 物料 0 或 >64、BOM 边 >4,096、需求或到货 >10,000 |
| `InvalidItem` | SKU 为空、数量越界、提前期不在 `0..127`、批量政策非法 |
| `DuplicateItem` | 同一 SKU 出现两次 |
| `UnknownItem` | BOM 或移动单据引用不存在的物料 |
| `InvalidComponent` | 父项等于子项、单位用量不在 `1..10^9` |
| `DuplicateComponent` | 同一父子边重复 |
| `InvalidMovement` | ID 为空或重复、周期越界、数量 ≤0 或越界 |
| `DuplicateMovement` | 同一集合内 `id` 重复 |
| `Cycle` | 拓扑排序中仍有未访问节点；列表含环的下游节点 |
| `QuantityLimit` | 每期聚合、`gross+safety`、`available`、批量舍入或结存超过 `10^12` |
| `BeforeHorizon` | 某计划下达早于第 0 期；报出物料、收货期与计算出的下达期 |

## 7. 输出与确定性

- 物料按 SKU 的 UTF-16 字典序输出；订单按 SKU、收货期；Peg 按 SKU、周期、来源（独立需求先于父项订单）。
- 输入行顺序不影响结果；`plan` 复制输入数组后排序，不修改调用方数据。
- 同一输入重复调用得到相同计划；`Plan`、`ItemPlan`、`Bucket`、`Order`、`Peg`、`PlanningError` 都实现 `Eq` 与 `Debug`，便于直接断言。
