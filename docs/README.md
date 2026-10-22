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
3. **要验证算法是否自洽，跑 `python3 docs/ALGORITHM_SELF_CHECK.py 200`**。
   它用题目参数生成合成被试跑通整条链路，输出离散度、可靠性相关与标定建议。
   注意：合成数据来自模型自身，只能验证自洽性，不构成对真实人群的效度证据。
4. **要看几套换算方案在同一批作答上分别给出什么，跑 `python3 docs/ALGORITHM_COMPARISON.py`**。
   对比表见 [韦氏风格量表分换算说明](WECHSLER_STYLE_SCORING.md)的「几套换算方案的对比」。
5. **要复核题目难度，跑 `python3 docs/ITEM_DIFFICULTY_AUDIT.py`**。
   它按分测验报告不同能力水平下的预期得分率，指出哪些分测验偏难、难度是否整齐，
   以及 A/B 题组的参数关系。
6. **改了题目参数或换算公式之后，跑 `python3 docs/run_all.py`**（一次跑完全部诊断）。
   其中门禁 `run_diagnostics.py` 用固定种子、固定规模的合成被试算出关键指标，与基线文件比对，
   偏差超容差就以非零退出码失败——防止一次「顺手的小改动」悄悄改坏标定而无人察觉。
   结果是确定性的（同样的输入必得同样的数字），所以比对的是精确值而非统计噪声。
   检查项包括合成分离散度、各分测验难度基准的均值与标准差，以及一个对任何题目参数改动都敏感的指纹。
   入口还会做一次一致性核对：`calibrate_slopes.py` 与 `ALGORITHM_SELF_CHECK.py` 是两套独立实现，
   它们在同一批合成被试上给出的建议斜率必须一致，否则说明其中之一改坏了。
   有意改动后用 `python3 docs/run_diagnostics.py --update` 重新建立基线。
   - 换算参数的唯一真源是 `IQTest/Resources/ScoringCalibration.json`，生产代码与分析脚本共用，
     单元测试断言两边一致。
   - `scripts/hooks/pre-commit` 会在这类改动提交前自动跑门禁。
7. **已经收集到真实作答数据、要开始参数拟合，跑 `python3 docs/calibration_export.py <导出的JSON> [输出目录]`**。
   它把应用导出的历史 JSON 转成拟合需要的题目表、作答表、被试表与难度基准表，并给出数据质量检查。
8. **要把题目参数标定出来，跑 `python3 docs/fit_item_parameters.py <上一步的输出目录>`**。
   联合极大似然交替优化每道题的难度与区分度——这是当前**最大的精度瓶颈**：
   所有题目的区分度都被设为 1.0，每题只区分「会不会」，不区分「擅长到什么程度」。
   `--study 40,80,160,320` 可看出标定误差随样本量的变化，标定 240 题需要多少被试一目了然；
   `--synthetic N` 用真值已知的合成被试检验脚本本身是否正确。
9. **要用真实数据重新标定合成分斜率，跑 `python3 docs/calibrate_slopes.py <上一步的输出目录>`**。
   它复用自检的同一套估计流程但换成真实作答，实测尺度分之和的离散度，据此反推「让合成分标准差回到 15」的斜率。
   用 `--synthetic 60` 可在真值已知的情况下检验脚本本身是否正确。
10. **要提升测量精度，看 [IQ_ESTIMATION.md](IQ_ESTIMATION.md) 的「怎样有证据地接近韦氏」**，
   其中列出了需要真实样本才能完成的步骤；开始采集前先读 [COLLECTION_PLAN.md](COLLECTION_PLAN.md)
   的方案（分阶段样本量、招募分层、知情同意与分析顺序）。
