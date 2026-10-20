# moon-mrp

仓库：[sun-zhao12/moon-mrp](https://github.com/sun-zhao12/moon-mrp)（MIT）。纯 MoonBit 的离散周期、多层物料需求计划库。输入 BOM、独立需求、期初库存、预计到货、提前期、安全库存和订货批量政策；输出每种物料逐期的毛需求、净需求、计划收货、计划下达、预计结存，以及可回溯到需求或父项订单的毛需求贡献。

它解决“该补多少、何时下达、这个子件需求从哪里来”。这是无限产能假设下的物料计划，不是车间排程或采购执行系统。所有计算使用有界 Int64 整数，JSON 中数量统一写成十进制字符串。

## 三种工作流

1. **装配与共享子件**：计划员输入第 5 期 9 套 KIT、期初 1 套库存、两层 BOM 与 MODULE 备件需求；计划补 KIT 10、MODULE 16，RAW 分别补 43 和 10。RAW 同时被 KIT 和 MODULE 使用，在所有父项贡献到齐后统一净算。
2. **门店/仓库补货**：输入 LABEL 期初 3、安全库存 2、第 1 期需求 9、第 2 期需求 3、到货 2、最小订购量 10 且倍数为 4，得到第 1 期补货 12，结存继续覆盖后续需求。
3. **供应承诺变更重算**：维修计划输入 PART 库存 2、第 3 期需求 8，计划补货 6；供应商确认第 2 期到货 3 后，使用同一 API 重算，计划补货降为 3。旧计划和输入保持不变，可由业务系统自行比较并审批。

示例另外演示提前期不足、BOM 成环时拒绝输出计划。

`examples/replenishment` 是第二个可独立运行的示例：单店补货，最小订购量 10、倍数 4、安全库存 2、提前期 1，逐期打印毛需求／到货／净需求／收货／下达／结存，并用一份独立库存递推断言每个周期的守恒关系，同时演示不建计划的 `order_quantity`。

## 本地运行

已发布到 Mooncakes：[`sun-zhao12/moon-mrp` 0.1.0](https://mooncakes.io/modules/sun-zhao12/moon-mrp)，可以直接 `moon add sun-zhao12/moon-mrp`，也可以按下述命令克隆源码运行。只依赖工具链自带标准库，无第三方模块依赖。本次验证的工具链是 `moon 0.1.20260920` / `moonc v0.10.14+7d59c7ec9`；Wasm、WasmGC、JS 三个目标已实际构建并运行，Native 需要本机 C 编译器（本次本机 C 编译器编译工具链自带 runtime 失败，详见 `LOCAL_VALIDATION.md`）。

```powershell
git clone https://github.com/sun-zhao12/moon-mrp
Set-Location moon-mrp
moon check --deny-warn --target all
moon build --target all
moon test --deny-warn --target all
moon run examples/demo --target wasm --deny-warn
moon run examples/replenishment --target wasm --deny-warn
moon fmt --check
moon info
```

`moon` 不在 PATH 时，把 `$MOON_HOME\bin` 加进当前进程 PATH 即可；本仓库不安装或改动工具链。`moon fmt --check` 与 `moon info` 只在 0.10.14 工具链上验证通过；换成更新的稳定版后，格式化器会把 `Int` 写成 `Int32`、`x?` 写成 `x~`，出现差异属于工具链版本差异，不是源码错误。

## API

```moonbit
let request : @mrp.Request = {
  horizon: 4,
  items: [{ sku: "PART", on_hand: 2L, safety_stock: 0L, lead_time: 1, lot: LotForLot }],
  bom: [],
  demands: [{ id: "repair", item: "PART", bucket: 3, quantity: 8L }],
  receipts: [],
}
let result = @mrp.plan(request).unwrap()
// quantity=6, receipt_bucket=3, release_bucket=2
println(result.to_json().stringify())
```

包导入为 `"sun-zhao12/moon-mrp" @mrp`；完整可编译调用见 `examples/demo`。`plan` 返回 `Result[Plan, PlanningError]`；`order_quantity` 可单独调用，验证非负净需求并执行批量舍入。完整签名见 `pkg.generated.mbti`。

## 计划语义

- 周期编号为 `0..horizon-1`，不隐含天、周、时区或工作日。`on_hand` 是第 0 期期初已有库存；`receipts` 在所属期可用，不可向前借用。
- 先验证全部输入与整个 BOM，再按父项优先的确定性拓扑序净算。即使暂时无需求，成环、自引用、非法数量或未知引用也不能被忽略。
- 每期 `available = 上期结存 + 本期到货`，`net = max(0, 毛需求 + 安全库存 - available)`；按批量规则求计划收货，然后扣毛需求得到结存。安全库存是每期期末下限，不是每期重复加入的毛需求。
- `LotForLot` 按净需求；`Multiple(m)` 向上取倍数；`MinimumMultiple(min,m)` 先满足最小量，再取倍数。净需求为 0 时不发单，即便有最小订购量。
- 计划收货提前 `lead_time` 期下达；**只有新计划下达的父项数量**按 BOM 生成子项毛需求。现货及已排定父项到货不再消耗一次子件。
- 如果任何计划下达早于第 0 期，返回 `BeforeHorizon(item, receipt_bucket, release_bucket)`，整次计算不返回部分计划；扩展前置空周期或调整已知到货后重新运行。绝不把负周期偷偷移到第 0 期。
- `Peg` 记录独立需求 ID 或父项计划订单（父项 SKU、收货期）对某个子项某期的毛需求贡献，其合计等于对应 `gross`。它不是安全库存分摊或逐个现货批次分配证明。
- 输出 SKU 与 ID 使用 UTF-16 字典序，订单按 SKU/收货期排列；行输入顺序不影响结果，不修改调用方数组。`Cycle` 的列表是拓扑中被阻塞的节点，可包含环的下游节点，不宣称每项都在环上。

逐期公式、完整数字示例、错误与上限表见 [docs/semantics.md](docs/semantics.md)。

## 输入与数值边界

最多 64 个物料、128 个周期、4,096 条 BOM 边，独立需求与预计到货各最多 10,000 条。需求 ID 在需求集合内唯一，到货 ID 在到货集合内唯一；同 ID 的重复行也拒绝，不隐含重试去重。

物料名非空唯一，父子边唯一且引用已有物料。提前期为 0..127，单位用量、批量倍数和最小批量为 1..10 亿。库存、安全库存、单笔数量、每期聚合量、`gross+safety`、`available`、批量舍入结果和预计结存上限均为 `10^12`；所有数量为整数，需求和到货必须大于 0。乘法前用除法检查上界，不先做可能溢出的乘法。达到边界时返回 `QuantityLimit`，不截断或饱和。

不处理有限机器产能、供应商实际可交付性、替代料、损耗率、小数单位、保质期、成本优化、采购事务或跨批次状态。安全库存和 BOM 由调用方提供，不代表系统替用户决定政策。样例全部虚构。

## 发布到 Mooncakes

0.1.0 已由 [`.github/workflows/publish.yml`](.github/workflows/publish.yml) 发布：本机只能访问 `github.com`，runner 有完整外网，因此上传在 CI 里完成。工作流用仓库 secret `MOONCAKES_TOKEN` 写入 `~/.moon/credentials.json`，校验源码后执行 `moon publish --dry-run` 与 `moon publish`，最后回读注册表。

发布完成后可核对：

```powershell
moon add sun-zhao12/moon-mrp          # 从注册表拉取 0.1.0
curl https://mooncakes.io/api/v0/modules/sun-zhao12/moon-mrp
```

回读结果：`version = 0.1.0`、`build_status = success`。发布包 26 个文件，不含 `申报书.md`、`_build` 与 `.github`。

需要发新版本时，改 `moon.mod` 的 `version` 后手动触发 `Publish to Mooncakes`（`workflow_dispatch`，可选 `check_only` 只看注册表），或推送 `v*` 标签。手工发布的等价命令是 `moon login`（sun-zhao12）→ `moon publish --dry-run` → `moon publish`；注意当前的 `moon publish --dry-run` 在服务端返回 `202 Accepted` 之后仍会以非零码退出，这是该版本的行为，不影响正式发布。

## 实现与验证

实现分为显式模型、全量输入检查、拓扑净算/需求贡献、JSON 输出。测试覆盖共享子件、库存与到货抵扣、安全库存、提前期、无效图与引用、输入顺序、整数边界、JSON 导出字段与 Peg 来源、批量政策边界、UTF-16 排序、重复计算确定性与文档化规模上限；每目标 34 项具名测试，另以逐个枚举订单数量核对 4,212 组批量输入、以独立库存模拟核对 256 组需求日历。命令结果见 `LOCAL_VALIDATION.md`。

CI 配置覆盖 `moon check`、`moon build`、`moon test` 与两个示例的四目标运行。格式化不作为门禁：新版工具链的格式化器会把 `Int` 规范化成 `Int32`、把可选参数 `x?` 改写为 `x~`，而 0.10.14 完全不接受 `Int32`，两代格式化器无法同时满足；源码采用在两者上都能编译的写法。本地验证通过 Wasm、WasmGC、JS（Native 受阻于本机 C 编译器）；线上 CI 在 `moonc v0.10.16` 上四目标各 34 项测试与两个示例全部通过，运行记录见 `LOCAL_VALIDATION.md`。Mooncakes 已发布 0.1.0 且 `build_status = success`。仓库不含 `申报书.md`（已忽略，仅留本地供本人核对改写）；未提交报名。

MIT。相邻项目、通用方法与有限检索范围见 [SOURCES.md](SOURCES.md)；不承诺无任何重叠或必然过审。
