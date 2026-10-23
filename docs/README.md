# 文档索引

按「什么时候需要看什么」排列。全部文档都遵循同一条底线：自编题库没有人群常模，
因此任何输出都不能解释为正式韦氏 IQ，也不解释为同龄人排名。

| 文档 | 讲什么 | 什么时候读 |
| --- | --- | --- |
| [SCORING.md](SCORING.md) | 计分口径、每个报告项的含义、与正式韦氏的差距、要提供有依据的 IQ 需要补什么 | 想知道某个数字代表什么、能用来做什么时 |
| [WECHSLER_STYLE_SCORING.md](WECHSLER_STYLE_SCORING.md) | 韦氏风格量表分剖面的完整算法、换算参数来源、标定状态与已知偏差 | 要改算法、复核换算或解释数值来源时 |
| [IQ_ESTIMATION.md](IQ_ESTIMATION.md) | 单参数能力模型的概率假设、参数文件、输出门槛与验证路径 | 要理解或调整能力估计时 |
| [ADMINISTRATION.md](ADMINISTRATION.md) | 施测流程、操作示例、计时、中断与提前结束的处理规则 | 要改答题交互或计时逻辑时 |
| [HISTORY_STORAGE.md](HISTORY_STORAGE.md) | 历史记录的落盘方式、迁移与损坏隔离、导出格式 | 要改数据存储或导出时 |
| [HISTORY_AND_EXIT.md](HISTORY_AND_EXIT.md) | 完成状态、结束并保存、记录详情的展示规则 | 要改历史页展示时 |
| [QUESTION_BANK_EXPANSION.md](QUESTION_BANK_EXPANSION.md) | 题库扩充与答案复核的逐项记录 | 改题库内容前先看这里 |
| [COLLECTION_PLAN.md](COLLECTION_PLAN.md) | 真实样本采集方案：阶段、招募、知情同意、操作流程与分析计划 | 要开始收集数据时 |
| [COLLECTION_INSTRUCTIONS.md](COLLECTION_INSTRUCTIONS.md) | 面向参与者的说明，可直接转发 | 招募被试时 |

## 建议阅读顺序

1. **先读 [SCORING.md](SCORING.md)** 建立边界认识：哪些结论可以说、哪些不能说。
   这份文档记录了项目为什么拒绝输出正式 FSIQ、人群百分位与年龄加分。
2. **要动算法就读 [WECHSLER_STYLE_SCORING.md](WECHSLER_STYLE_SCORING.md)**，
   特别是「标定状态与已知偏差」一节——当前斜率是借用的，
   在本项目的题目参数下会让合成分的离散度与目标 15 分不符。
3. **要验证算法是否自洽，跑 `python3 docs/ALGORITHM_SELF_CHECK.py --grid 5`**。
   它用题目参数生成合成被试跑通整条链路，输出离散度、可靠性相关与标定建议。
   `--grid 5` 用固定能力网格（21 点、每点 5 次取平均）代替随机抽样：随机抽 60 个 θ 时，
   θ 的实现标准差会在 0.88–0.93 之间摆动，让同一个量给出相差 5% 以上的离散度，
   而斜率改动带来的变化往往只有 2–4%。
   **加 `--per-subtest 12` 才是使用者实际遇到的施测情形**（每分测验 12 题、共 120 题）；
   两个口径给出的建议斜率相差 40%，引用数字时必须写明用的是哪个。
   注意：合成数据来自模型自身，只能验证自洽性，不构成对真实人群的效度证据。
4. **要看几套换算方案在同一批作答上分别给出什么，跑 `python3 docs/ALGORITHM_COMPARISON.py`**。
   对比表见 [韦氏风格量表分换算说明](WECHSLER_STYLE_SCORING.md)的「几套换算方案的对比」。
   表中的「重新标定后」用的建议斜率是脚本从自检流程**动态复算**的（全部题目作答口径），
   不是写死的常数——写死会随题目参数与公式的变化悄悄过期。
5. **要复核题目难度，跑 `python3 docs/ITEM_DIFFICULTY_AUDIT.py`**。
   它按分测验报告不同能力水平下的预期得分率，指出哪些分测验偏难、难度是否整齐，
   以及 A/B 题组的参数关系。
6. **要扩充题库，跑 `python3 tools/generate_wechsler_items.py --batches N`**。
   `--batches N` 连续产出 N 批、每批换一批新题，并按内容去掉与题库重复的——
   只换种子不换逻辑，产出的往往正是题库里已有的那批。
   先用 `--check` 看「会新增多少道真新题」，再决定要不要写入；写入后要重建诊断基线
   （`python3 docs/run_diagnostics.py --update`）。各分测验还能扩多少，
   `tools/check_generator_consistency.py` 每次都会报告。细节见
   [题库扩充说明](QUESTION_BANK_EXPANSION.md)。
   瑞文题库用 `python3 tools/generate_raven_items.py`（同样支持 `--check`），
   它的生成器会跳过与现有题库重复的题干。
   题库出问题时还有两个只报告不修改的检查：`tools/repair_raven_answer_keys.py --check`
   （答案键与解析是否一致）与 `tools/repair_raven_duplicate_prompts.py --check`
   （去掉空白后是否有重复题干）。
7. **改了题目参数或换算公式之后，跑 `python3 docs/run_all.py`**（一次跑完全部诊断）。
   其中门禁 `run_diagnostics.py` 用固定种子、固定规模的合成被试算出关键指标，与基线文件比对，
   偏差超容差就以非零退出码失败——防止一次「顺手的小改动」悄悄改坏标定而无人察觉。
   结果是确定性的（同样的输入必得同样的数字），所以比对的是精确值而非统计噪声。
   检查项包括两种施测口径下的合成分离散度（题库全做完、真实一轮 120 题）、
   各分测验难度基准的均值与标准差，以及一个对任何题目参数改动都敏感的指纹。
   入口还会跑 `docs/MEASUREMENT_PRECISION.py`（测量精度与区分度敏感性）、
   `docs/ITEM_DIFFICULTY_AUDIT.py`（逐分测验难度）与 `docs/ALGORITHM_COMPARISON.py`
   （几套换算方案的输出对比）。
   入口还会做一次一致性核对：`calibrate_slopes.py` 与 `ALGORITHM_SELF_CHECK.py` 是两套独立实现，
   **两个脚本都会真的跑起来**，在同一批合成被试上比较它们给出的建议斜率；
   只比一个手抄的常数是发现不了自检脚本自身被改坏的。
   入口还会跑两项路径级检查：
   - `tools/check_generator_consistency.py`：题库与生成器是否还对得上
     （只改其中一方，下次跑生成器就会把另一方的修正覆盖回去）；
   - `calibrate_slopes.py --selfcheck`：真实标定路径「应用导出 → csv → 标定」的
     端到端往返是否无损。
   有意改动后用 `python3 docs/run_diagnostics.py --update` 重新建立基线。
   - 换算参数的唯一真源是 `IQTest/Resources/ScoringCalibration.json`，生产代码与分析脚本共用，
     单元测试断言两边一致。
   - `scripts/hooks/pre-commit` 会在这类改动提交前自动跑门禁。
8. **已经收集到真实作答数据、要开始参数拟合，跑 `python3 docs/calibration_export.py <导出的JSON> [输出目录]`**。
   它把应用导出的历史 JSON 转成拟合需要的题目表、作答表、被试表与难度基准表，并给出数据质量检查。
9. **要把题目参数标定出来，跑 `python3 docs/fit_item_parameters.py <上一步的输出目录>`**。
   联合极大似然交替优化每道题的难度与区分度——这是当前**最大的精度瓶颈**：
   所有题目的区分度都被设为 1.0，每题只区分「会不会」，不区分「擅长到什么程度」。
   `--study 40,80,160,320` 可看出标定误差随样本量的变化，标定 480 题需要多少被试一目了然；
   `--synthetic N` 用真值已知的合成被试检验脚本本身是否正确。
   注意这个瓶颈是**相对于「每轮每分测验只做 12 题」这个施测设计**而言的：
   合成复算显示，把区分度从 1.0 提到 2.0，12 题情形的折合标准误从 5.08 降到 3.59；
   但若每轮做满题池（48 题），区分度提升几乎无收益（2.09 → 2.53，反而变差）。
   **在参数尚未拟合、缺真实样本的阶段，「每轮多做题」比「提高区分度」更可行**——
   后者要重新拟合全部题目参数，前者只要改抽题数。
10. **要用真实数据重新标定合成分斜率，跑 `python3 docs/calibrate_slopes.py <上一步的输出目录>`**。
   它复用自检的同一套估计流程但换成真实作答，实测尺度分之和的离散度，据此反推「让合成分标准差回到 15」的斜率。
   接受的是**完整作答的一轮记录**（每轮每分测验 12 题、共 120 题），不要求把题库 480 题全做完——
   后者按生产的施测设计根本做不到。
   用 `--synthetic 60` 可在真值已知的情况下检验脚本本身是否正确（输出会与自检脚本逐位对照）。
   用 `--selfcheck 60` 做**端到端自检**：造合成被试 → 写成应用导出格式 →
   走 `calibration_export.py` 的文件往返 → 再算一遍，核对往返前后离散度一致。
   真实数据要走的就是这条链，它曾经两处逻辑失效（要求覆盖全部 480 题、
   把 `None` 送进相关系数）而表面看不出来。`run_all.py` 每次都会跑这一项。
   注意它的输出带有 `normalizationBasis` 字段：真实作答没有能力真值，
   只能采用「真实人群能力标准差为 1」的先验假设，该假设未经常模验证——
   按实测归一化与按先验假设，两条路径给出的建议斜率可差 16%，采信前要想清楚用哪条。
11. **要提升测量精度，看 [IQ_ESTIMATION.md](IQ_ESTIMATION.md) 的「怎样有证据地接近韦氏」**，
   其中列出了需要真实样本才能完成的步骤；开始采集前先读 [COLLECTION_PLAN.md](COLLECTION_PLAN.md)
   的方案（分阶段样本量、招募分层、知情同意与分析顺序）。
