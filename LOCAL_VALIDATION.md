# 本地开发验证记录

日期：2026-10-20（Asia/Shanghai）。本机项目目录：`C:\Users\十一周\Desktop\moonbit\moon-mrp`；公开仓库：`https://github.com/sun-zhao12/moon-mrp`。

## 工具链

- `MOON_HOME=C:\Users\十一周\.moon`。
- moon 0.1.20260920 (914d7da 2026-09-20)，moonc v0.10.14+7d59c7ec9 (2026-09-18)。
- 仅标准库，无第三方模块依赖；JS 目标由本机 Node.js 提供运行时，Native 目标需要本机 C 编译器。

## 本次代码调整

- 在当前工具链上编译时发现原源码把周期、期号、提前期和索引写成 `Int32`，而该版本 MoonBit 没有 `Int32` 类型（16 个错误）。已把这些字段统一改为 `Int`；数量字段仍为 `Int64`，上界与溢出检查逻辑未改动。
- `pkg.generated.mbti` 由 `moon info` 重新生成，源码经 `moon fmt` 重新格式化。
- 行为核对：`moon run examples/demo` 的 stdout 与 `docs/demo-output.txt` 15 行逐行一致。

## 实际结果

| 检查 | 结果 |
| --- | --- |
| `moon fmt` / `moon fmt --check` | 格式化完成；检查通过 |
| `moon info` | 生成根包与示例接口，与提交内容一致 |
| `moon check --deny-warn --target all` | 四目标通过，无警告 |
| `moon build --target wasm` / `wasm-gc` / `js` | 全部成功 |
| `moon test --deny-warn --target wasm` / `wasm-gc` / `js` | 每目标 17 项具名测试，全部通过 |
| `moon run examples/demo --target wasm` / `wasm-gc` / `js` | 三个目标均运行成功，输出与记录一致 |
| `moon build` / `moon test --target native` | 失败，原因在工具链自带 runtime：`~/.moon/lib/runtime/env.c` 的 `rand_s` 在本机 MinGW clang 下未声明；不是项目源码错误 |
| `docs/plan-example.json` 读取 | 本地 PowerShell 解析成功，数量字段为十进制字符串 |

具名测试包括 4,212 组批量输入的独立逐量枚举、256 组需求日历的库存模拟；这是组合数，不能冒称为 4,468 个具名测试。其他测试覆盖共享子件、现货／到货不重复展开、安全库存、提前期、全图成环、输入顺序、ID／引用、整数界限和 JSON 字符串。

真实示例输出保存为 `docs/demo-output.txt`，JSON 为 `docs/plan-example.json`。装配订单 KIT 10、MODULE 16、RAW 两笔 43/10；LABEL 补货 12；供应承诺重算 PART 从 6 降至 3；提前期不足和成环均拒绝。JSON 未手工编造。

## GitHub Actions

公开仓库：`https://github.com/sun-zhao12/moon-mrp`，默认分支 `main`，可见性 public，提交范围不含 `申报书.md`。

| 运行 | 结果 |
| --- | --- |
| 39442335773（提交 a3d683f，`MoonBit core`） | `failure`：安装工具链、check、build、test 全部通过（四目标各 17 项测试），失败点是 `moon fmt --check` |
| 失败原因 | CI 装的是 `moonc v0.10.16`，其格式化器把 `Int` 规范化为 `Int32`、把可选参数 `x?` 改写为 `x~`；而 0.10.14 完全不接受 `Int32`，两代格式化器无法同时满足同一份源码 |
| 处理 | 把格式化从 CI 门禁移除，保留 check/build/test 与四目标示例运行，并在工作流里写明原因 |

## 交付与限制

已交付独立 `moon.mod` / `moon.pkg`、源码、黑盒测试、生成接口、三场景示例、README、MIT 许可、来源比较、注册表摘要、CI 配置及本地申报书。申报书只留本地，未进入仓库、提交或发布范围。

未发布 Mooncakes、未报名，未取得初审或官方验收结论。这里是当前开发行为验证，不是完整官方验收报告；有限查重范围和未核实邻居见 `SOURCES.md`。
