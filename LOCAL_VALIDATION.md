# 本地开发验证记录

日期：2026-10-22（Asia/Shanghai）。本机项目目录：`C:\Users\十一周\Desktop\moonbit\moon-mrp`；公开仓库：`https://github.com/sun-zhao12/moon-mrp`。

## 工具链

- `MOON_HOME=C:\Users\十一周\.moon`。
- 本机：moon 0.1.20260920 (914d7da 2026-09-20)，moonc v0.10.14+7d59c7ec9 (2026-09-18)。
- CI：`moonc v0.10.16+b1a0e846e`（安装脚本装最新 stable）。
- 仅标准库，无第三方模块依赖；Native 目标需要本机 C 编译器。

## 0.2.0 的改动

按 2026-10-22 初审意见逐项补齐，技术细节见 `CHANGELOG.md`、`docs/semantics.md`、`docs/scenarios.md`：

- 数量改为定点小数 `Qty`（3 位，`Qty::int` / `Qty::milli`），全流程 Int64 溢出检查与向上取整。
- 新增 `Item.yield_per_mille`（良率）、`Component.scrap_per_mille`（损耗）、`Component.usage_unit` + `Request.conversions`（单位换算，缺换算报 `InvalidConversion`）。
- 批量政策扩为六种：`LotForLot`、`FixedQuantity`、`Multiple`、`MinimumMultiple`、`PeriodOrder(n)`、`MinMax(min, max)`。
- 提前期不足：`ReleasePolicy::Strict` 拒绝；`AllowLate` 钳到第 0 期，输出 `Order.late` 与 `Plan.incidents`。
- 规模上限：4096 物料、1024 周期、100000 BOM 边、100000 单据、提前期 4096。
- `Bucket.received` 记录合格入库量；JSON 升为 `moon-mrp.plan.v2`。

## 实际结果（本机 0.10.14）

| 检查 | 结果 |
| --- | --- |
| `moon fmt` / `moon fmt --check` | 格式化完成；检查通过 |
| `moon info` | 生成根包与两个示例接口，与提交内容一致 |
| `moon check --deny-warn --target all` | 四目标通过，无警告 |
| `moon build --target wasm` / `wasm-gc` / `js` | 全部成功 |
| `moon test --deny-warn --target wasm` / `wasm-gc` / `js` | 每目标 49 项具名测试全部通过 |
| `moon run examples/demo` / `examples/replenishment` | 三个本地目标均运行成功，输出与 `docs/demo-output.txt` 一致 |
| `moon build` / `moon test --target native` | 本机仍失败于工具链自带 runtime 的 `rand_s`（MinGW clang 未声明），不是项目源码错误；CI 的 Ubuntu Native 通过（49/49） |

测试覆盖：多层共享子件、到货抵扣、安全库存、提前期、图验证、输入顺序、整数上界、JSON v2 字段、六种批量政策、损耗、良率、单位换算、POQ、Min-Max、late incident、规模上限；另有 4,212 组批量枚举、256 组需求日历，以及 324 组单层组合的独立模拟对照（`features_test.mbt`）。

## GitHub Actions

公开仓库：`https://github.com/sun-zhao12/moon-mrp`，默认分支 `main`，可见性 public，提交范围不含 `申报书.md`、`修复备注.md`。

| 运行 | 结果 |
| --- | --- |
| 39772233905（提交 ed550d7） | `success`：0.2.0 源码，四目标各 49 项测试通过，两个示例 × 四目标运行成功 |
| 39772350280（Publish to Mooncakes） | `success`：`moon publish` 上传 0.2.0；回读 `version 0.2.0`、`build_status queued` |
| 39772435072（`check_only`） | `success`：回读 `version 0.2.0`、`build_status success` |

## Mooncakes

- 包：`sun-zhao12/moon-mrp`，最新版本 **0.2.0**，`build_status = success`。
- 安装：`moon add sun-zhao12/moon-mrp`。
- 发布方式：本机出网只放行 `github.com`（`mooncakes.io` 在 `moon`、`python`、多个代理端口上均为 `tls handshake eof` / `502`），因此由 `.github/workflows/publish.yml` 在 runner 上执行，凭据来自仓库 secret `MOONCAKES_TOKEN`（对应 `moon whoami = sun-zhao12`）。
- 发布包 26 个文件，不含 `申报书.md`、`_build`、`.github`。

## 交付与限制

已交付独立 `moon.mod` / `moon.pkg`、定点数量模块、源码、49 项测试、生成接口、两个可运行示例、README、语义文档、场景对照文档、CHANGELOG、MIT 许可、来源说明、CI 与发布工作流及本地申报材料。申报书与修复说明只留本地。

仍未交付或未验证：与商业 ERP 的实测对比（只有公开文档口径对照）、有限产能与替代料、保质期与成本优化、多工厂、采购执行。这些属于明确的边界，不写成已实现能力。
