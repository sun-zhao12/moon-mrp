# moon-mrp

仓库：[sun-zhao12/moon-mrp](https://github.com/sun-zhao12/moon-mrp)（MIT）· Mooncakes：`sun-zhao12/moon-mrp` 0.3.0

纯 MoonBit 的离散周期、多层物料需求计划库，覆盖 MRP 计划内核：需求输入、BOM 展开、库存与补货政策、批量、提前期与异常、可追溯输出。输入 BOM、独立需求、期初库存、预计到货、提前期、安全库存策略、损耗率、良率、单位换算和批量政策；输出每种物料逐期的毛需求、净需求、计划收货、合格入库、计划下达、预计结存，以及可回溯到需求或父项订单的毛需求贡献。

它解决"该补多少、何时下达、这个子件需求从哪里来"。这是无限产能假设下的物料计划，不是车间排程或采购执行系统。数量使用定点小数（3 位小数），全流程 Int64 溢出检查，JSON 中数量是十进制字符串。与 frePPLe、ERPNext MRP 的逐项对照见 [docs/capability.md](docs/capability.md)。

## 七种工作流

1. **装配与共享子件**：计划员输入第 5 期 9 套 KIT、期初 1 套库存、两层 BOM 与 MODULE 备件需求；计划补 KIT 10、MODULE 16，RAW 分别补 43 和 10。RAW 同时被 KIT 和 MODULE 使用，在所有父项贡献到齐后统一净算。
2. **门店/仓库补货**：输入 LABEL 期初 3、安全库存 2、第 1 期需求 9、第 2 期需求 3、到货 2、最小订购量 10 且倍数为 4，得到第 1 期补货 12，结存继续覆盖后续需求。
3. **供应承诺变更重算**：维修计划输入 PART 库存 2、第 3 期需求 8，计划补货 6；供应商确认第 2 期到货 3 后，使用同一 API 重算，计划补货降为 3。旧计划和输入保持不变。
4. **良率、损耗、小数用量与单位换算**：PANEL 良率 95%，1 台用 2500 G 涂料、损耗 20%，涂料基础单位 KG。计划 PANEL 8.422，涂料需求 25.268 KG。
5. **期间订货量**：`PeriodOrder(3)` 把随后 3 期的净需求合成一张订单，避免每期小单。
6. **提前期不足**：默认严格策略拒绝整次计算；`AllowLate` 把下达钳到第 0 期，标记 `late` 并输出 incident 供加急决策。
7. **虚拟件、安全库存策略与再订货点**：虚拟件透传展开；安全库存可选固定值、需求天数或需求百分比；`ReorderPoint(level, quantity)` 实现"再订货点 + 再订货量"；超过 `max_stock` 的结存进入 `exceptions`。

示例另外演示安全库存下限、到货不可前置借用、BOM 成环时拒绝输出计划。

## 本地运行

从 Mooncakes 安装：`moon add sun-zhao12/moon-mrp`；或克隆源码运行：

```powershell
git clone https://github.com/sun-zhao12/moon-mrp
Set-Location moon-mrp
moon check --deny-warn --target all
moon test --deny-warn --target all
moon run examples/demo --target wasm --deny-warn
moon run examples/replenishment --target wasm --deny-warn
```

只依赖工具链自带标准库，无第三方模块依赖。本次验证工具链是 `moon 0.1.20260920` / `moonc v0.10.14+7d59c7ec9`；Wasm、WasmGC、JS 已实际构建运行，Native 需要本机 C 编译器。`moon fmt --check` 与 `moon info` 只在 0.10.14 上验证通过（换新稳定版后格式化器会把 `Int` 写成 `Int32`、`x?` 写成 `x~`，属于工具链版本差异，不是源码错误）。

## API

```moonbit
let request : @mrp.Request = {
  horizon: 4,
  items: [{
    sku: "PART",
    unit: "EA",
    on_hand: @mrp.Qty::int(2),
    safety: @mrp.SafetyStock::Fixed(@mrp.Qty::int(1)),
    max_stock: @mrp.Qty::zero(),
    lead_time: 1,
    yield_per_mille: 1000,
    lot: @mrp.LotForLot,
    phantom: false,
  }],
  bom: [],
  demands: [{ id: "repair", item: "PART", bucket: 3, quantity: @mrp.Qty::int(8) }],
  receipts: [],
  conversions: [],
  policy: @mrp.Strict,
}
let result = @mrp.plan(request).unwrap()
// safety 1, on_hand 2, demand 8 at bucket 3, lead 1:
// net 7, quantity 7, receipt_bucket 3, release_bucket 2
println(result.to_json().stringify())
```

包导入为 `"sun-zhao12/moon-mrp" @mrp`；完整可编译调用见 `examples/`。`plan` 返回 `Result[Plan, PlanningError]`；`order_quantity(net, lot)` 可脱离日历单独验证批量取整。完整签名见 `pkg.generated.mbti`。

## 计划语义

- `Qty` 是定点小数：`Qty::int(2)` 为 2，`Qty::milli(250)` 为 0.25，最小步长 0.001。
- 周期编号 `0..horizon-1`；`on_hand` 是第 0 期期初库存；到货只在所属期可用。
- 每期 `available = 上期结存 + 到货`，`net = max(0, 毛需求 + safety(t) - available)`；订单先按良率放大，再按批量政策取整，合格入库 `received = floor(订单 * 良率 / 1000)`。
- `SafetyStock`：`Fixed(q)`、`DaysOfDemand(n)`（全周期平均需求 × n）、`PercentOfDemand(p)`（当期满需求 × p%）。
- `LotRule`：`LotForLot`、`FixedQuantity`、`Multiple`、`MinimumMultiple`、`PeriodOrder(n)`、`MinMax(min, max)`、`ReorderPoint(level, quantity)`。
- 子件需求只由父项计划订单产生，并按 `units_per * (1 + 损耗)` 与换算因子折算，每个乘法向上取整到 0.001。
- `phantom` 物品不持有库存、不生成订单，其毛需求在同一周期直接展开给子件。
- 下达早于第 0 期：`Strict` 返回 `BeforeHorizon`；`AllowLate` 钳到第 0 期并记录 incident。
- `Peg` 记录独立需求或父项订单的贡献，合计等于对应周期的毛需求；超过 `max_stock` 的期进入 `exceptions`。
- 输出按 SKU/周期/来源确定性排序，输入行顺序不影响结果，不修改调用方数组。

逐期公式、错误表、规模上限与完整推导见 [docs/semantics.md](docs/semantics.md)；十四组典型场景的对照数字与验证出处见 [docs/scenarios.md](docs/scenarios.md)；与 frePPLe / ERPNext MRP 的逐项对照见 [docs/capability.md](docs/capability.md)。

## 输入与数值边界

最多 4096 种物料、1024 个周期、100000 条 BOM 边，独立需求与预计到货各最多 100000 条。需求 ID 在需求集合内唯一，到货 ID 在到货集合内唯一；同 ID 重复行也拒绝。

物料名非空唯一，父子边唯一且引用已有物料。提前期 `0..4096`，良率 `1..1000`（千分比），损耗 `0..1000`，`units_per` 与批量值必须为正，安全库存策略取 `Fixed` / `DaysOfDemand(0..1024)` / `PercentOfDemand(0..100)`。虚拟件不得带期初库存、安全库存、上限或到货。库存、单笔数量、每期聚合量、`gross+safety`、`available`、批量舍入结果和预计结存上限均为 `10^12` 个单位；乘法前先做除法/溢出检查，超限返回 `QuantityLimit`，不截断、不饱和。

不处理有限机器产能、供应商实际可交付性、替代料、保质期、成本优化、采购事务或跨批次状态；这些属于应用层或优化层，逐项说明见 [docs/capability.md](docs/capability.md) 第 6 节。损耗、良率、换算、安全库存和批量政策由调用方提供，不代表系统替用户决定政策。样例全部虚构。

## 实现与验证

实现分为定点数量、显式模型、全量输入检查、拓扑净算（安全库存/损耗/良率/换算/批量）、虚拟件透传、提前期与异常策略、JSON 输出。每目标 **56 项具名测试**，覆盖共享子件、到货抵扣、安全库存三种策略、提前期、图验证、输入顺序、整数上界、JSON 字段与 Peg、七种批量政策、损耗与良率、单位换算、POQ、Min-Max、再订货点、虚拟件、late incident、过量异常、规模上限；另有 4,212 组批量枚举、256 组需求日历和对 324 组单层组合的独立模拟对照。

CI 覆盖 `moon check`、`moon build`、`moon test` 与两个示例的四目标运行；发布由 `.github/workflows/publish.yml` 在 runner 上执行 `moon publish` 并回读注册表。运行记录见 [LOCAL_VALIDATION.md](LOCAL_VALIDATION.md)。仓库不含 `申报书.md`（本地保留）。

## 版本与升级

0.2.0 相对 0.1.0 是有意的破坏性升级：

| 0.1.0 | 0.2.0 |
| --- | --- |
| 数量是 `Int64` 整数单位 | 数量是 `Qty` 定点小数（3 位），用 `Qty::int` / `Qty::milli` 构造 |
| `Item` 含 `sku/on_hand/safety_stock/lead_time/lot` | 增加 `unit`、`yield_per_mille` |
| `Component` 含 `parent/child/units_per` | 增加 `usage_unit`、`scrap_per_mille` |
| `Request` 无换算与策略 | 增加 `conversions`、`policy` |
| `Bucket` 无 `received` | 增加 `received`（合格入库） |
| JSON `moon-mrp.plan.v1` | `moon-mrp.plan.v2`，增加 `received`、`late`、`incidents` |
| 上限 64 物料 / 128 周期 | 4096 物料 / 1024 周期 / 100000 单据 |

0.3.0 的变化：

- `Item.safety_stock: Qty` → `Item.safety: SafetyStock`，新增 `Item.max_stock`、`Item.phantom`。
- 新增 `LotRule::ReorderPoint(level, quantity)`。
- `Plan` 新增 `exceptions: Array[StockException]`；JSON 升为 `moon-mrp.plan.v3`。

## 许可证与来源

MIT。相邻项目、通用方法与有限检索范围见 [SOURCES.md](SOURCES.md)；典型场景的算法对照见 [docs/scenarios.md](docs/scenarios.md)；能力矩阵见 [docs/capability.md](docs/capability.md)。
