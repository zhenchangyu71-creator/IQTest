# 智商测试（IQTest）

SwiftUI 应用，iOS 17+，由 XcodeGen 管理工程。

- **瑞文推理模块**：432 道自编混合推理题，四种题型 × 三种难度，每个组合 36 题，每轮抽 12 题，优先抽没做过的题。报告实验性 IQ 估算（未校准）及 95% 估计区间，不提供人群百分位或年龄常模解释。
- **韦氏风格练习**：480 道自编题，A/B 两个题组各 240 题，均包含 10 个分测验、每项 24 题；每轮每分测验抽 12 题，优先抽没做过的题。首页可选择本轮题组，单项练习从两组中抽取 3 题。报告原始成绩，并按韦氏的量表分结构输出**未校准**的分测验尺度分、领域指数分、全量表分、百分位与等级描述。仍不提供正式 FSIQ 与人群常模。两组尚未等值，分数不能直接比较。

本应用不提供正式 WAIS/WISC 施测。题目、答题媒介和限时规则为本应用的练习设计，没有适配题库的年龄常模、信效度研究或专业施测支持。

## 瑞文答题流程

- 点击有效选项时立即锁定答案并计分，展示约 0.8 秒对错反馈后再换题；反馈期间不继续扣作答时间。
- 按单调时钟的截止时刻计算剩余时间，点击提交时再次检查；到达截止时刻的答案按超时未答处理，不依赖计时器是否及时刷新。
- 每次出题使用独立提交标识，拒绝重复提交、旧题事件及上一轮测试的残留提交。下一题从实际呈现时获得完整作答时间。
- 计时器延迟（包括切后台后返回）最多使当前已呈现题超时，不连续消耗后续题。最后一题反馈结束后只保存一次成绩。

## 结果说明、历史与提前结束

- 瑞文估算保留数值，去掉经验年龄加分、全球排名与人群评价；新结果单独保存模型版本，旧 IQ 数据保留但不继续当作有效估算展示。
- 新记录保存题目、实际选项评分、答案、解析和用时快照，历史列表可打开详情；旧记录缺少的题干不从当前题库重建。
- 完整练习可“结束并保存已答题”。未完成记录只报告已记录项目，不产生 IQ、不更新最佳成绩、不展示未答题解析。
- 历史不再混合汇总不同模型和难度的 IQ。详细规则见 [历史与结束流程](docs/HISTORY_AND_EXIT.md)。
- 历史使用逐条原子文件保存，迁移旧数据前保留原始备份；损坏条目单独提示，保存失败可重试。支持模块/状态筛选、单条移除和用户选择位置的 JSON 导出。见 [历史保存与导出](docs/HISTORY_STORAGE.md)。

## 韦氏模块本次完善

- 240 题都有稳定题号与解析；保留 A 组题号，B 组使用独立 `b-` 前缀；修复积木、矩阵、拼图、词义和常识中的歧义或错误表述。
- 数字广度改为自由输入回忆，支持顺序、逆序、升序；不展示备选项。刺激仍为屏幕视觉呈现，与正式听觉施测不同。
- 校验题号唯一性、分测验完整性、选项与分值数量、分值范围、唯一满分答案、数字刺激及回忆规则。
- 所选题组的 10 个分测验完整作答，取消未经验证的统一“三题零分即停测”规则。不宣称文件题序为已校准难度。
- 完整练习与单项练习共用同一答题引擎。按单调时钟的截止时刻计时，提交时再次检查超时；旧题的重复提交不能给下一题计分。
- 每个分测验先阅读说明、完成独立的不计分操作示例，准备好后才开始计分题；分测验间可休息。
- 失去前台时进入中断页，保留已答题且不推进后台后续题；确认继续后将受影响题标为未计分。报告与历史保存流程版本、中断阶段和时长。
- 保存逐题答案、分值、超时状态、用时、题库版本和开始时的年龄；练习结束后可展开逐题解析。
- 完整报告按韦氏标准十分法输出量表分剖面：分测验尺度分（1–19，附标准九分与 95% 估计区间）、领域指数分、全量表分、百分位与等级描述，以及由 Fisher 信息传播的 95% 区间。尺度分来自按逐题参数推断的能力参数，指数分与全量表分对尺度分之和的换算关系参照 Pearson 官方示例报告；题目参数未经样本拟合，也没有人群常模，因此百分位只表示本练习上的相对位置，区间只反映本题库内的测量误差。分测验尺度分只有 12 题支撑，区间宽达 ±5–9 分，差异落在区间内不代表能力高低；领域之间是否真的不同，按各领域自身的估计误差判断，不套用固定差值门槛。结果页还列出本题库中一贯更难的分测验（如数字广度），避免把题目难度误读成能力弱，并给出本次得分率与本题库平均预期的对照。同时展示原始分、领域原始分、分测验得分率和超时数。雷达图各轴已按该分测验的难度基准归一，外圈表示达到本题库平均水平。
- 旧版估算记录保留原数据，但不继续按旧公式展示 IQ 或人群排名。
- 单项练习合并 A/B 两组，按组内题序排序后分成前、中、后三段，各抽一题；得分率单独保存，零分与尚未练习正确区分。旧 1–19 量表分不会被误读为百分比。

本轮扩充及答案复核说明见 [题库扩充记录](docs/QUESTION_BANK_EXPANSION.md)。增加题量和替换重复题目不等同于提高 IQ 测量精度。

## 计分规则与精度边界

原始总分是已完成项目得分之和。本题库言语题按 0/1/2 分计，其余按 0/1 分计，完整练习满分 **156 分**。0/1/2 是自编评分规则：选择最完整、准确或概括的答案可得满分，部分描述可得 1 分，不是官方开放式言语评分。

得分率 = 原始分 ÷ 相应计分题满分 × 100%，四舍五入为整数。它只描述本组题表现，**不是人群百分位**。超时计零分并单独标记；中断题标为未计分并排除出分母。存在中断时只报告其余题目成绩，不生成 IQ，也不更新单项练习最佳成绩。全部中断时不显示数值得分率。具体流程与规则见 [施测流程说明](docs/ADMINISTRATION.md)。

年龄在测试开始时固定保存。实验性 IQ 模型尚未按年龄校准；韦氏模块不再按儿童、青少年或老年身份人工加分。首页允许输入 6–99 岁只是基本信息录入，并不代表这些年龄均已验证适用本题库。

当前按韦氏的量表分结构呈现结果，但每一环都还没有人群常模支撑：尺度分由能力参数换算而来，指数分与全量表分对尺度分之和的换算关系来自对公开示例报告数值的核对，区间由 Fisher 信息传播并以韦氏手册的实测水平为下限。这些参数与先验都是初始假设，模型条件的先验分布不是人群常模，估算结果不进入瑞文趋势。三题练习、项目中断、大量超时或模型不匹配时不输出剖面。

借用斜率的前提在本项目不成立：每个分测验只有 12 题，能力估计被压窄，[算法自检脚本](docs/ALGORITHM_SELF_CHECK.py) 显示当前输出的合成分离散度约为 17 分而非 15 分，能力差异的放大程度与韦氏并不一致。按本项目数据重新标定的建议值已算出但未实施，需真实样本才能定案。算法细节见 [韦氏风格量表分换算说明](docs/WECHSLER_STYLE_SCORING.md)。

未来如果需要有测量依据的 IQ，需要专业团队确定量表版本、语言、目标人群和施测方式，并取得匹配题目与媒介的常模及验证数据。正式量表的转换表不能直接套在本应用自编题上。详见 [计分与验证说明](docs/SCORING.md)和[IQ 算法与校准路径](docs/IQ_ESTIMATION.md)。

## 主要目录

```text
IQTest/
  Models/Wechsler.swift             # 题目、回忆规则、题库校验、原始成绩汇总
  Models/WechslerIQEstimator.swift  # 分层能力估计、模型校验与 Fisher 标准误
  Models/WechslerAbility.swift      # 总体与分测验能力参数
  Models/WechslerProfile.swift      # 尺度分、指数分、全量表分与置信区间换算
  Models/IQScale.swift              # 正态量尺、百分位与韦氏式等级描述
  Resources/WechslerIQModel.json    # 启发式逐题参数，非实测常模
  Resources/ScoringCalibration.json # 换算标定参数的唯一真源（生产代码与分析脚本共用）
  Models/TestRecord.swift           # 新旧历史数据兼容与完成状态
  Models/RecordedItem.swift         # 当次题目、刺激和评分的历史快照
  Models/HistoryFilter.swift        # 模块、完成状态与时间排序
  Models/RecordExport.swift         # 版本化 JSON 导出，保留原始成绩
  Models/RavenIQEstimate.swift      # 瑞文模块未校准估算与模型版本
  Models/WechslerInstructions.swift # 独立的不计分操作示例与指导
  Models/WechslerQuestionSet.swift  # A/B 题组与资源选择
  Models/WechslerAdministration.swift # 流程版本与中断记录
  ViewModels/WechslerViewModel.swift # 共享计时、作答、结果与保存
  ViewModels/PracticeViewModel.swift # 单项练习入口及独立练习成绩存储
  Views/WechslerQuizView.swift       # 完整练习
  Views/RecallAnswerView.swift       # 数字回忆输入
  Views/WechslerInstructionsView.swift # 分测验准备与示例
  Views/WechslerInterruptionView.swift # 中断确认与过程报告
  Views/WechslerResultView.swift     # 原始分报告与逐题解析
  Views/TestRecordDetailView.swift   # 历史详情与当次快照回顾
  Views/RecordSaveStatusView.swift   # 保存失败重试与离开确认
  Views/RecordExportButton.swift     # 系统文件保存入口
  Views/SubtestPracticeView.swift    # 单项练习
  Views/PracticeRadarView.swift      # 得分率雷达图
  Resources/Questions.json          # 288 道自编推理题
  Resources/Wechsler.json           # A 组 120 道自编练习题
  Resources/WechslerB.json          # B 组 120 道自编练习题
  Resources/WechslerIQModelB.json   # B 组独立的启发式参数
  Services/ItemExposureStore.swift   # 已做题目记录，抽题时优先选没做过的
tools/generate_wechsler_items.py      # 韦氏题库扩充生成器（固定种子，可复现）
tools/generate_raven_items.py         # 瑞文题库扩充生成器
docs/COLLECTION_PLAN.md            # 真实样本采集方案与知情同意要点
  Services/RecordArchive.swift      # 逐条历史文件、迁移、异常隔离与原始备份
Tests/WechslerTests.swift            # 计分、计时、校验、历史兼容测试
Tests/QuizViewModelTests.swift       # 瑞文截止时间、反馈、防重复提交与保存测试
Tests/QuestionBankExpansionTests.swift # 新题组可达性、完整流程、参数匹配与题库校验
Tests/RecordArchiveTests.swift       # 落盘、迁移中断、损坏隔离与清理
Tests/RecordSaveRetryTests.swift     # 保存失败与幂等重试
Tests/HistoryExportTests.swift       # 筛选与 JSON 导出
Tests/WechslerProfileTests.swift     # 量表分换算、Pearson 基准、剖面一致性与编码兼容
Tests/RavenIQEstimateTests.swift     # 瑞文估算与 Wilson 得分区间
docs/                               # 文档索引见 docs/README.md
docs/ALGORITHM_SELF_CHECK.py          # 合成被自检：标定状态、离散度与可靠性相关
docs/ALGORITHM_COMPARISON.py          # 几套换算方案在同一批作答上的输出对比
docs/ITEM_DIFFICULTY_AUDIT.py         # 题目难度诊断：预期得分率、难度整齐度、A/B 参数关系
docs/calibration_export.py            # 历史导出 → 参数拟合数据集与数据质量检查
docs/calibrate_slopes.py              # 用真实作答重新标定合成分斜率
docs/run_diagnostics.py               # 诊断门禁：标定与难度指标相对基线是否劣化
docs/run_all.py                       # 一次跑完全部诊断的入口
docs/diagnostics_baseline.json        # 诊断基线（由 run_diagnostics.py 建立）
UITests/                            # 黑盒 UI 测试 harness
project.yml                        # 应用及单元测试工程配置
```

## 抽题轮换

每轮题量保持不变（推理 12 题、韦氏 120 题），但抽题会**优先选没做过的题**：应用按题库记录已做过的题号，
下一次测试避开它们，题池全部做过后才重新开始一轮。

这条规则针对的是重复出题的真实代价——看过解析再遇到同一题，复测分数必然虚高，多次测量也失去意义。
韦氏模块的题池因此从每分测验 12 题扩到 24 题，推理模块从 288 题扩到 432 题。

扩充题目由 `tools/` 下的生成器产生，固定种子可复现，生成后逐题校验唯一满分、选项不重复、题干不重复。
新题的难度参数按题目结构估计（数字广度按位数、算术按结果大小），不是随机采样——
那会让题目实际难度与参数脱节，反而污染分数。但这些参数与旧题同样未经真实数据标定，
**增加题量与减少重复都不构成 IQ 精度验证**。

## 题库格式

```json
{
    "id": "digitspan-01",
    "subtest": "digitspan",
    "prompt": "请记住下面的数字，随后请按【相同顺序】回忆。",
    "options": ["4 8 2", "2 8 4", "8 4 2", "4 2 8"],
    "optionScores": [1, 0, 0, 0],
    "presentation": "digits",
    "stimulus": "4 8 2",
    "displaySeconds": 4,
    "recallRule": "forward",
    "explanation": "按原顺序回忆，应输入：482。"
}
```

数字题的 `options` 仅用于题库答案校验，不显示给作答者；计分依据 `stimulus` 与 `recallRule` 独立求出。`recallRule` 支持 `forward`、`backward`、`ascending`。输入接受半角/全角数字和空白，拒绝其他字符，保留前导零，必须完整匹配。

题号应稳定；题目或评分变更后应更新 `WechslerLoader.bankVersion`。所有分测验至少三题，才能支持分段抽题。校验失败时显示错误，不开始测试或保存默认成绩。

## 构建与测试

需要 Xcode、iOS Simulator 和 XcodeGen。源文件及 target 配置变更后重新生成工程。

```bash
xcodegen generate
xcrun simctl list devices booted

# 将 <模拟器ID> 替换为本机 ID
xcodebuild test -project IQTest.xcodeproj -scheme IQTest \
  -destination 'platform=iOS Simulator,id=<模拟器ID>' \
  -derivedDataPath /tmp/iqtest-derived CODE_SIGNING_ALLOWED=NO

# UI harness 驱动已安装应用，必须先安装刚构建的版本
xcrun simctl install <模拟器ID> \
  /tmp/iqtest-derived/Build/Products/Debug-iphonesimulator/IQTest.app
xcodegen generate --spec UITests/project.yml
xcodebuild test -project UITests/UITestHarness.xcodeproj -scheme UITestHarness \
  -destination 'platform=iOS Simulator,id=<模拟器ID>' \
  CODE_SIGNING_ALLOWED=NO

# 算法自检：用题目参数生成合成被试，检查换算链路的统计性质
python3 docs/ALGORITHM_SELF_CHECK.py 200
python3 docs/ALGORITHM_SELF_CHECK.py 200 --json   # 机器可读输出

# 几套换算方案在同一批作答上的输出对比
python3 docs/ALGORITHM_COMPARISON.py

# 题目难度诊断：各分测验的预期得分率、难度是否整齐、A/B 参数关系
python3 docs/ITEM_DIFFICULTY_AUDIT.py

# 把历史导出转成参数拟合数据集（items/responses/persons/baselines + 质量检查）
# 可给多个导出文件或一个目录，多人采集的多个文件会被合并
python3 docs/calibration_export.py <导出的JSON或目录> [...] [-o 输出目录]

# 用真实作答重新标定合成分斜率（需要上一步的输出目录）
python3 docs/calibrate_slopes.py <上一步的输出目录>
python3 docs/calibrate_slopes.py --synthetic 60   # 用合成被试检验脚本本身

# 诊断门禁：标定与难度指标相对基线是否劣化（有意改动后用 --update 重建基线）
python3 docs/run_diagnostics.py

# 一次跑完全部诊断（改动题目参数、换算公式或标定文件后）
# 含一致性核对：两套独立实现给出的建议斜率必须一致
python3 docs/run_all.py
```

单元测试覆盖全对、全错、部分得分、120 题完整施测、156 分满分、实验性估算的概率模型/输出门槛、不生成正式 FSIQ、时间边界、刺激阶段计时、非法输入、重复提交、损坏题库、版本存储、旧数据兼容、题目快照、提前结束及练习成绩。量表分剖面另有专门测试：正态量尺与韦氏示例报告数值的核对、尺度分之和到指数分与全量表分的换算、置信区间下限、分层估计的收缩行为、领域差异的显著性判断、分测验难度基准、得分率与本题库平均预期的对照、标定参数与共享配置文件的一致性、顺序无关性与编码兼容。瑞文另有 Wilson 得分区间的测试。UI 测试覆盖瑞文流程、韦氏完整练习、单项练习、数字输入、两个模块提前结束后的历史详情、B 题组的选择与身份保持，以及历史筛选、导出与单条移除。

瑞文回归测试使用可控时钟，覆盖临近截止时刻提交、反馈跨越截止时刻、计时器延迟与重复刷新、重复/过期/越界提交、重置重开，以及全对和全超时的完整 12 题保存流程。

UI 测试还覆盖操作示例和切后台后确认恢复，会修改模拟器中的年龄、练习和历史数据。单元测试备份并恢复其涉及的 UserDefaults 键。请顺序运行同一台模拟器的单元与 UI 测试，避免互相抢占应用。测试证明程序行为，不构成心理测量信效度证据。
