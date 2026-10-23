import SwiftUI

/// 自编题库报告原始表现与明确标注的量表分剖面。
struct WechslerResultView: View {
    @EnvironmentObject private var vm: WechslerViewModel

    private func confidenceText(_ lower: Int?, _ upper: Int?) -> String {
        guard let lower, let upper else { return "95% 区间不可估计" }
        return "95% 区间 \(lower)–\(upper)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                RecordSaveStatusView(error: vm.saveError, retry: vm.retrySave)
                VStack(spacing: 8) {
                    Text(vm.endedEarly ? "本次练习提前结束" : "本次练习报告").font(.headline)
                    if let set = vm.sessionQuestionSet {
                        Text(set.title + " · 题组尚未等值").font(.caption).foregroundStyle(.secondary)
                    }
                    if let profile = vm.profile {
                        Text("韦氏风格量表分").font(.subheadline)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(profile.fullScale.score)")
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .foregroundStyle(.purple)
                                .accessibilityIdentifier("profileFullScaleScore")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("全量表分").font(.subheadline)
                                Text(confidenceText(profile.fullScale.confidenceLower, profile.fullScale.confidenceUpper))
                                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        Text("\(profile.fullScale.band.rawValue) · 百分位 ≈ \(Int(profile.fullScale.percentile.rounded()))")
                            .font(.headline).foregroundStyle(.secondary)
                        Text("年龄仅作记录、未参与换算 · 不等同正式韦氏 IQ")
                            .font(.caption).foregroundStyle(.secondary)
                        if let overall = profile.overallRate, let bankAverage = profile.bankAverageRate {
                            Text("本次答对 \(Int((overall * 100).rounded()))%，而本题库在模型平均能力下的预期是 \(Int((bankAverage * 100).rounded()))%。分数反映的是相对本题库的位置。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(profile.flags, id: \.rawValue) { flag in
                            Text(flag.message).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("本次未生成量表分剖面").font(.headline)
                        Text(vm.estimationNote ?? "作答或模型参数不足")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(vm.maxRaw > 0 ? "\(vm.rawScore) / \(vm.maxRaw)" : "暂无计分成绩")
                        .font(.title2.bold())
                        .foregroundStyle(.purple)
                        .accessibilityIdentifier("wechslerRawScore")
                    Text(vm.maxRaw > 0 ? "原始分 · 已计分题得分率 \(vm.performancePercentage)%" : "全部项目均未计分")
                        .font(.subheadline)
                    Text("记录 \(vm.responses.count)/\(vm.itemCount) 题 · 超时 \(vm.timedOutCount) 题 · 中断 \(vm.interruptedCount) 题 · \(vm.sessionAge) 岁")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(WechslerLoader.scoringNotice)
                        .font(.footnote).foregroundStyle(.secondary)
                    if vm.hasPriorPractice {
                        Text("已存在练习或复测记录，熟悉题目可能影响本次表现。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding(.top, 20)

                WechslerAdministrationView(administration: vm.administration).reportCard()

                if let profile = vm.profile {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("领域指数分").font(.headline)
                        ForEach(profile.indices) { index in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(index.domain.rawValue)
                                    Spacer()
                                    Text("\(index.score)").font(.headline).monospacedDigit()
                                }
                                HStack(spacing: 12) {
                                    Text("百分位 ≈ \(Int(index.percentile.rounded()))")
                                    Text(index.band.rawValue)
                                    Text(confidenceText(index.confidenceLower, index.confidenceUpper))
                                }
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                        }
                        Text("指数分 Mean 100 / SD 15，由该领域两个分测验的尺度分之和换算。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("各领域的换算刻度并不一致：以合成被试复算真实一轮 120 题的施测情形，言语约 15 分、知觉约 14 分、记忆约 11 分、加工速度约 10 分，而量表设计值都是 15 分。刻度不同，领域之间的分差就不能直接当作能力差异。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .reportCard()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("分测验尺度分").font(.headline)
                        ForEach(profile.subtests) { scaled in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(scaled.subtest.rawValue)
                                    Spacer()
                                    Text("尺度分 \(scaled.scaled)").monospacedDigit()
                                    if let lower = scaled.confidenceLower, let upper = scaled.confidenceUpper {
                                        Text("(\(lower)–\(upper))").monospacedDigit()
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("九分 \(scaled.standardNine)").monospacedDigit()
                                    Text(scaled.band.rawValue).font(.caption)
                                }
                                .font(.subheadline)
                            }
                        }
                        Text("尺度分 Mean 10 / SD 3，范围 1–19。括号内是 95% 估计区间：每个分测验只有 12 题，区间通常宽达 ±6–14 分，两个分测验的差异落在各自区间内时并不代表能力高低。九分是尺度分按标准正态切成的九档粗分，1 最低、9 最高。")
                            .font(.caption).foregroundStyle(.secondary)
                        let harder = profile.subtests.compactMap { scaled -> (String, Int)? in
                            guard let baseline = scaled.baselineRate else { return nil }
                            let percent = Int((baseline * 100).rounded())
                            return percent < 70 ? (scaled.subtest.rawValue, percent) : nil
                        }
                        if !harder.isEmpty {
                            Text("本题库中一贯更难的分测验：" + harder.map { "\($0.0)（θ=0 预期得分率 \($0.1)%）" }.joined(separator: "、") + "。这些分测验的尺度分偏低，不宜直接解读为能力较弱。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .reportCard()

                    if let comparisons = profile.domainComparisons, !comparisons.isEmpty {
                        let significant = comparisons.filter { $0.significant }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("领域之间是否存在显著差异").font(.headline)
                            if significant.isEmpty {
                                Text("四个领域之间没有达到 95% 置信水平的差异。本次表现较为均衡，或本次作答量不足以区分领域高低。")
                                    .font(.subheadline)
                            } else {
                                ForEach(significant) { comparison in
                                    HStack {
                                        Text("\(comparison.first.rawValue) vs \(comparison.second.rawValue)")
                                        Spacer()
                                        Text("差 \(abs(comparison.difference)) 分").monospacedDigit()
                                    }
                                    .font(.subheadline)
                                }
                                Text("差异按各领域自身的估计误差计算，置信水平 95%。这是本次结果的统计差异，不是能力诊断。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .reportCard()
                    }
                }

                DisclosureGroup("量表分是怎样换算的？") {
                    Text("作答先按题目难度参数推断能力参数，再换算成韦氏标准十分法的尺度分（Mean 10 / SD 3），由尺度分合成领域指数分与全量表分（Mean 100 / SD 15）。指数分与全量表分对尺度分之和的换算关系参照 Pearson 官方示例报告，置信区间由 Fisher 信息传播得到。")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    Text("题目参数、能力分布与换算表都是初始假设，没有本应用题库的人群常模，也没有与正式韦氏的对照效度。因此百分位只表示本练习上的相对位置，不能解释为同龄人排名，区间也不包含未校准带来的系统偏差。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("换算斜率借用自韦氏官方示例报告，其前提是「尺度分之和的离散度与韦氏题库相同」。本项目每个分测验只有 12 题，这个前提并不成立。以合成被试复算真实一轮 120 题的施测情形，输出的全量表分标准差约为 13 分，而量表设计值是 15 分——同样的能力差距在页面上会被压缩。各领域的刻度也不一致，因此领域之间的分差不宜直接当作能力强弱。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let profile = vm.profile {
                        Text("模型版本：\(profile.modelVersion) · 校准状态：未校准")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .reportCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("领域原始分").font(.headline)
                    ForEach(WechslerDomain.allCases) { domain in
                        let value = vm.result(for: domain)
                        HStack {
                            Text(domain.rawValue)
                            Spacer()
                            Text(value.maxRaw > 0 ? "\(value.raw) / \(value.maxRaw)" : "无计分项目").monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                }
                .reportCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("分测验得分率").font(.headline)
                    PracticeRadarView(scores: WechslerSubtest.allCases.map { sub in
                        vm.results.first { $0.subtest == sub && $0.maxRaw > 0 }?.percentage
                    }, showCaption: false, baselines: vm.profile.map { profile in
                        WechslerSubtest.allCases.map { sub in
                            profile.subtests.first { $0.subtest == sub }?.baselineRate
                        }
                    })
                    Text("各轴已按该分测验的难度基准归一，外圈表示达到该分测验的本题库平均水平。原始得分率因各分测验难度不齐，直接横向比较会得出错误结论。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .reportCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("分测验原始分").font(.headline)
                    ForEach(vm.results) { result in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(result.subtest.rawValue)
                                Spacer()
                                Text(result.maxRaw > 0 ? "\(result.raw)/\(result.maxRaw) · \(result.percentage)%" : "未计分 · —")
                                    .monospacedDigit()
                            }
                            ProgressView(value: Double(result.raw), total: Double(max(1, result.maxRaw)))
                                .tint(.purple)
                            Text("计分 \(result.answered)/\(result.total) 题 · 超时 \(result.timedOut) 题 · 中断 \(result.interrupted) 题")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
                .reportCard()

                WechslerReviewView(responses: vm.responses, item: vm.item(for:))

                if let record = vm.completedRecord { RecordExportButton(records: [record]) }
                ResultExitActions(hasUnsavedRecord: vm.saveError != nil,
                                  again: { vm.start(questionSet: vm.sessionQuestionSet ?? .a) }, home: vm.reset)
                Text("题库版本：\(WechslerLoader.bankVersion)")
                    .font(.caption2).foregroundStyle(.secondary).padding(.bottom, 20)
            }
            .padding(.horizontal, 24)
        }
    }
}

struct WechslerReviewView: View {
    let responses: [WechslerResponse]
    let item: (WechslerResponse) -> WechslerItem?

    var body: some View {
        DisclosureGroup("逐题得分与解析（\(responses.count) 题）") {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(responses) { response in
                    if let question = item(response) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(question.subtest.rawValue) · \(question.order) · " + (response.outcome == .interrupted ? "未计分" : "\(response.score)/\(response.maxScore) 分"))
                                .font(.subheadline.bold())
                            Text(question.prompt).font(.subheadline)
                            Text(response.outcome == .interrupted ? "应用离开前台，本题中断，不计入得分率分母"
                                 : response.outcome == .timedOut ? "作答超时，计 0 分" : "你的答案：\(response.answer ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(question.explanation).font(.caption)
                            Text("题号 \(question.id) · 用时 \(String(format: "%.1f", response.elapsedSeconds)) 秒")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                }
            }
            .padding(.top, 12)
        }
        .reportCard()
    }
}

private extension View {
    func reportCard() -> some View {
        self.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
