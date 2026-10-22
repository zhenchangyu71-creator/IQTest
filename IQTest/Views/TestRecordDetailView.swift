import SwiftUI

struct TestRecordDetailView: View {
    let record: TestRecord
    var onDeleted: () -> Void = {}
    var keepsLegacyBackup = false
    @Environment(\.dismiss) private var dismiss
    @State private var showDelete = false
    @State private var deleteError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(record.testType.title).font(.title2.bold())
                if let set = record.questionSet {
                    Text(set.title + " · 题组尚未等值").font(.subheadline).foregroundStyle(.secondary)
                }
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline).foregroundStyle(.secondary)
                if record.completion == .endedEarly {
                    Text("未完成 · 不生成 IQ 估算").font(.headline)
                    if let planned = record.plannedItemCount {
                        Text("已记录 \(record.reviewItems?.count ?? record.responses?.count ?? 0)/\(planned) 题")
                    }
                } else if let value = record.profileValue ?? record.estimateValue {
                    Text((record.wechslerProfile == nil ? "实验性 IQ 估算 " : "全量表分 ") + "\(value)")
                        .font(.title2.bold()).foregroundStyle(.purple)
                    Text("未校准 · 年龄仅作记录、未参与换算").font(.subheadline)
                    if let profile = record.wechslerProfile {
                        Text("百分位 ≈ \(Int(profile.fullScale.percentile.rounded())) · \(profile.fullScale.band.rawValue)")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ForEach(profile.indices) { index in
                            Text("\(index.domain.rawValue) 指数分 \(index.score)").font(.caption).foregroundStyle(.secondary)
                        }
                        if !profile.subtests.isEmpty {
                            Divider()
                            Text("各分测验尺度分").font(.headline)
                            ForEach(profile.subtests) { scaled in
                                HStack {
                                    Text(scaled.subtest.rawValue)
                                    Spacer()
                                    Text("尺度分 \(scaled.scaled)").monospacedDigit()
                                    if let baseline = scaled.baselineRate {
                                        Text("本库基准 \(Int((baseline * 100).rounded()))%")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .font(.subheadline)
                            }
                            Text("本库基准是该分测验在模型平均能力下的预期得分率，越低说明这组题在本题库里一贯更难。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(record.iq == nil ? "本记录未生成 IQ 估算" : "旧版估算不作 IQ 解释")
                        .font(.headline)
                }
                Text("原始分 \(record.score)/\(record.total)")
                if let age = record.age { Text("开始时年龄：\(age) 岁") }
                Text(RavenIQEstimate.notice).font(.footnote).foregroundStyle(.secondary)
                if let version = record.scoringVersion { Text("题库：\(version)").font(.caption) }
                if let version = record.ravenEstimate?.modelVersion ?? record.iqEstimate?.modelVersion {
                    Text("模型：\(version)").font(.caption)
                }
                if let version = record.wechslerProfile?.scoringVersion {
                    Text("换算标定：\(version)").font(.caption)
                }
                if let administration = record.administration {
                    WechslerAdministrationView(administration: administration)
                    Text("流程：\(administration.protocolVersion)").font(.caption)
                }
                Divider()
                if let items = record.reviewItems {
                    Text("以下为当次保存的题目和评分快照，不随题库更新重算。")
                        .font(.caption).foregroundStyle(.secondary)
                    RecordedItemsView(items: items)
                } else {
                    Text("旧记录未保存题目快照，无法还原当时的题干和解析。")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let responses = record.responses {
                        ForEach(responses) { response in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(response.subtest.rawValue) · \(response.itemID)").font(.headline)
                                Text(response.outcome == .interrupted ? "中断，未计分" : "得分 \(response.score)/\(response.maxScore)")
                                Text(response.answer.map { "记录的答案：\($0)" } ?? "未记录答案")
                            }.font(.subheadline)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("从历史移除", role: .destructive) { showDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("记录操作")
            }
        }
        .safeAreaInset(edge: .bottom) {
            RecordExportButton(records: [record]).padding(10).frame(maxWidth: .infinity).background(.regularMaterial)
        }
        .confirmationDialog(keepsLegacyBackup ? "从历史移除这条记录？旧版迁移备份仍保留，清空全部历史时才一并删除。" : "从历史移除这条记录？", isPresented: $showDelete, titleVisibility: .visible) {
            Button("确认移除", role: .destructive) {
                do { try RecordStore.delete(id: record.id); onDeleted(); dismiss() }
                catch { deleteError = error.localizedDescription }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("删除未完成", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("好") { deleteError = nil }
        } message: { Text(deleteError ?? "") }
    }
}

struct RecordedItemsView: View {
    let items: [RecordedItem]

    var body: some View {
        DisclosureGroup("逐题记录（\(items.count) 题）") {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(index + 1). \(item.group) · " + (item.outcome == .interrupted ? "未计分" : "\(item.score)/\(item.maxScore) 分"))
                            .font(.subheadline.bold())
                        Text(item.prompt).font(.subheadline).accessibilityIdentifier("recordedPrompt")
                        if let stimulus = item.stimulus {
                            Text("当时呈现：\(stimulus)").font(.subheadline.monospaced())
                                .accessibilityIdentifier("recordedStimulus")
                        }
                        if let rule = item.recallRule {
                            Text("回忆规则：\(recallDescription(rule))").font(.caption)
                        }
                        if let seconds = item.displaySeconds {
                            Text("序列呈现 \(seconds) 秒").font(.caption)
                        }
                        Text(answerDescription(item)).font(.caption).foregroundStyle(.secondary)
                        Text("满分答案：\(item.correctAnswer)").font(.caption)
                        Text(item.explanation).font(.caption)
                        if !item.options.isEmpty {
                            DisclosureGroup("当次选项与评分") {
                                ForEach(Array(item.options.enumerated()), id: \.offset) { _, option in
                                    Text("\(option.text) · \(option.score) 分").font(.caption)
                                }
                            }.font(.caption)
                        }
                        Text("用时 \(String(format: "%.1f", item.elapsedSeconds)) 秒")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }.padding(.top, 12)
        }
        .padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func answerDescription(_ item: RecordedItem) -> String {
        switch item.outcome {
        case .answered: return "你的答案：\(item.answer ?? "")"
        case .timedOut: return "超时，计 0 分"
        case .interrupted: return "中断，未计分，不计入得分率分母"
        }
    }

    private func recallDescription(_ rule: WechslerItem.RecallRule) -> String {
        switch rule {
        case .forward: return "按相同顺序"
        case .backward: return "按相反顺序"
        case .ascending: return "按从小到大顺序"
        }
    }
}
