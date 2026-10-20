# 来源、需求与有限查重

日期：2026-10-20，Asia/Shanghai。结论仅用于本地工程选题；不是全网唯一性证明或组委会初审结论。

## 范围与方法

实际读取 `https://mooncakes.io/api/v0/modules`，当次为 3,156 个模块；在名称、描述、关键词中检索 `BOM, bill of materials, material requirements, MRP, lot sizing, manufacturing, production planning`。部分摘要保存为 `docs/registry-neighbors.json`。

GitHub 仓库搜索实际成功查询：`moonbit "material requirements"`、`moonbit BOM MRP`、`language:MoonBit MRP in:readme`、`moonbit "BOM explosion"` 均返回 0，响应 `incomplete_results=false`。第一次 material requirements 查询出现 EOF，之后已重试并取得上述成功响应；不能把传输失败当作零结果。

这是公开注册表元数据与 GitHub 仓库/README 的有限检索，不是全量代码审计；中文同义词、未发布、私有、新建、搜索索引滞后等可能漏检。社区检索只覆盖注册表和公开 GitHub README/来源链接，未穷举论坛、群聊或私人讨论。

## 相邻能力比较

| 项目与核读范围 | 现有责任 | 本项目的关系与实际新增责任 |
| --- | --- | --- |
| [Bobojy00/moonbit-factory-graph](https://github.com/Bobojy00/moonbit-factory-graph)，Apache-2.0，未归档，观测 pushed_at=2026-08-24T07:33:46Z；核读 README、根 mbti、`src/analysis/capacity.mbt` | 工厂拓扑、多层流、故障传播、流量/生产资产吞吐能力与瓶颈分析；capacity 源码按目标需求率计算边与设备产能 | 同处制造工具领域且共享有向图知识，不称完全无交集。所读接口/实现未给出 BOM 单位展开、库存/到货抵扣、逐期批量订购及提前期反推。本库提供该独立物料计划责任；没有依赖、移植或完成上游产能互操作，也不以换名或增加界面为差异 |
| [cn-xjr/MoonPlan](https://github.com/cn-xjr/MoonPlan)、[ljs448/moonbitJobShop](https://github.com/ljs448/moonbitJobShop) | 本次注册表描述分别为有限域约束/排班、可扩展 job-shop 调度；本次未完整核查其源码和全部扩展 | 它们是正式申报前需继续复核的相邻规划能力，不把元数据不足当作排除其所有物料能力的证据。本库不声称求解排班、有限产能或最优调度 |
| 本机 `moon-usage` 与 `moon-change-window-auditor` | 前者计量定价，后者维护窗口碰撞与策略审查 | 无共同业务模型、源码、模块依赖、数据集或测试复用。本库按物料依赖和库存递推，不将已有单项目功能拆成多个报名项目 |

**有限结论：** 在成功查询与实际核读范围内，未发现相同的 BOM/逐期净算/批量/提前期核心模型；相邻规划项目的全部能力仍待复核。独立申报必要性与当月额度最终由官方判断；算法独立实现不自动等于无同类。

## 需求广度、实现深度与复用证据

- 装配计划：`Request` 的 BOM、销售与备件需求输入，经全图验证、父项拓扑净算到多层订单与 `Peg` 输出；共享原料测试验证多个父项贡献不能漏算或重复净算。
- 补货政策：不需要 BOM 也能使用 `order_quantity` 或 `plan`；安全库存、期初库存、预计到货、最小量/倍数政策共同决定各期订单，独立枚举核对批量最小值。
- 承诺变更：输入对象不变、仅替换预计到货后重算；示例从 6 单位降至 3，库不负责向供应商发单。

三种工作流共享合理的物料模型，不是三个行业名称替换。复用入口是 typed `plan`、独立的批量政策函数和确切 JSON 数据，而非单一 GUI 演示。可自然扩展为业务系统的数据适配，但当前不把未来接口或产能优化列成成果。

## 方法与许可证

MRP 的 BOM 逐层展开、按库存净算、lot-for-lot、提前期抵消等为通用工程方法，背景参考 [Material requirements planning](https://en.wikipedia.org/wiki/Material_requirements_planning)；该链接用于说明通用概念，本次没有逐项验证其当前正文，不宣称算法发明或某 ERP 产品兼容。

本期生产源码与测试独立编写，未复制上游代码、BOM 或企业数据；全部数量与 SKU 自行构造。仅使用 MoonBit 自带标准库。本项目 MIT；相邻项目许可不自动传入本库，因为没有复制或链接其实现。`registry-neighbors.json` 只保存公开调查摘要，不是运行时权威数据。

## 赛事来源与状态

依据本机 `moonbit-contest-projects` 技能包及其 2026-10-16 口径资料。它包含章程、历史月份与个案反馈摘要，本次没有把它称作在线获取的最新官方全文。历史微信来源此前已发现标题/月份与摘要不完全一致；当前报名额度、截止与材料规则需向官方确认。

本次只做本地开发与源码上传 GitHub，不执行报名、Release、Gitlink 同步或 Mooncakes 发布。申报书是参考草稿，只留本地，最终须由本人核对、理解和改写，不能宣称已满足章程的人工撰写要求。
