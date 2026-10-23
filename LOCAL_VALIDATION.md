# 本地开发验证记录

日期：2026-10-23（Asia/Shanghai）。本机项目目录：`C:\Users\十一周\Desktop\moonbit\moon-mrp`；公开仓库：`https://github.com/sun-zhao12/moon-mrp`。

## 工具链

- `MOON_HOME=C:\Users\十一周\.moon`。
- 本机：moon 0.1.20260920 (914d7da 2026-09-20)，moonc v0.10.14+7d59c7ec9 (2026-09-18)。
- CI：`moonc v0.10.16+b1a0e846e`（安装脚本装最新 stable）。
- 仅标准库，无第三方模块依赖；Native 目标需要本机 C 编译器。

## 0.3.0 的改动

第二轮评审要求以 frePPLe features 与 ERPNext MRP 文档作为功能完整性参考，并指出功能范围仍偏窄。本次补充（技术细节见 `CHANGELOG.md`、`docs/capability.md`）：

- 安全库存策略 `SafetyStock::{Fixed, DaysOfDemand, PercentOfDemand}`，逐期计算 `safety(t)`。
- 库存上限 `Item.max_stock` 与过量异常 `Plan.exceptions`（frePPLe excess inventory 工作流）。
- 再订货点规则 `LotRule::ReorderPoint(level, quantity)`（ERPNext reorder level + reorder qty）。
- 虚拟件 `Item.phantom`：透传展开，不持有库存、不生成订单。
- JSON 升为 `moon-mrp.plan.v3`，增加 `exceptions`。
- 新增 `docs/capability.md`：按两份参考逐项列出覆盖情况与明确边界。
- 测试 49 → **56 项/目标**；`docs/scenarios.md` 扩到十四组场景。

## 实际结果（本机 0.10.14）

| 检查 | 结果 |
| --- | --- |
| `moon fmt` / `moon fmt --check` | 格式化完成；检查通过 |
| `moon info` | 生成根包与两个示例接口，与提交内容一致 |
| `moon check --deny-warn --target all` | 四目标通过，无警告 |
| `moon build --target wasm` / `wasm-gc` / `js` | 全部成功 |
| `moon test --deny-warn --target wasm` / `wasm-gc` / `js` | 每目标 56 项具名测试全部通过 |
| `moon run examples/demo` / `examples/replenishment` | 三个本地目标均运行成功，输出与 `docs/demo-output.txt` 一致 |
| `moon build` / `moon test --target native` | 本机仍失败于工具链自带 runtime 的 `rand_s`（MinGW clang 未声明），不是项目源码错误；CI 的 Ubuntu Native 通过 |

测试覆盖：多层共享子件、到货抵扣、安全库存三种策略、提前期、图验证、输入顺序、整数上界、JSON v3 字段、七种批量政策、损耗、良率、单位换算、POQ、Min-Max、再订货点、虚拟件、late incident、过量异常、规模上限；另有 4,212 组批量枚举、256 组需求日历，以及 324 组单层组合的独立模拟对照。

## GitHub Actions

公开仓库：`https://github.com/sun-zhao12/moon-mrp`，默认分支 `main`，可见性 public，提交范围不含 `申报书.md`、`修复备注.md`。

| 运行 | 结果 |
| --- | --- |
| 39927799564（提交 4eeb0d0） | `success`：0.3.0 源码，四目标各 56 项测试通过，两个示例 × 四目标运行成功 |
| 39928005766（Publish to Mooncakes） | `success`：上传 0.3.0；回读 `version 0.3.0`、`build_status queued` |
| 39928091341（`check_only`） | `success`：回读 `version 0.3.0`、`build_status success` |

注意：用 `gh` 的 OAuth 凭据触发 `workflow_dispatch` 会返回 403（需要 admin 权限），本次改用带 `repo`+`workflow` 的 PAT 触发；仓库 secret `MOONCAKES_TOKEN` 不变。

## Mooncakes

- 包：`sun-zhao12/moon-mrp`，最新版本 **0.3.0**，`build_status = success`。
- 安装：`moon add sun-zhao12/moon-mrp`。
- 发布由 `.github/workflows/publish.yml` 在 runner 上执行（本机出网只放行 `github.com`，`mooncakes.io` 不可达）。
- 发布包 26 个文件，不含 `申报书.md`、`修复备注.md`、`_build`、`.github`。

## 交付与限制

已交付 `moon.mod` / `moon.pkg`、定点数量模块、源码、56 项测试、生成接口、两个可运行示例、README、语义文档、场景对照、能力矩阵、CHANGELOG、MIT 许可、来源说明、CI 与发布工作流及本地申报材料。申报书与修复说明只留本地。

明确边界（详见 `docs/capability.md` 第 6 节）：有限产能与排程、多地点分销、替代料自动选择、统计预测、UI/数据库/REST 集成。这些属于应用层或优化层，不在本库范围。
