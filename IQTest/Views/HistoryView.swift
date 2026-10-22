import SwiftUI

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [TestRecord] = []
    @State private var showClearConfirm = false
    @State private var filter = HistoryFilter()
    @State private var unreadableCount = 0
    @State private var loadError: String?
    @State private var operationError: String?
    @State private var hasLegacyBackup = false
    private var visible: [TestRecord] { filter.apply(to: records) }
    /// 当前筛选结果里出现的题组。两组题目不同且尚未等值，分数不能直接比较。
    private var visibleQuestionSets: [WechslerQuestionSet] {
        let sets = Set(visible.compactMap { $0.questionSet })
        return WechslerQuestionSet.allCases.filter { sets.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if hasLegacyBackup && loadError == nil {
                        Text("保留有旧版迁移备份。清空全部历史时会一并删除备份。")
                            .font(.caption).foregroundStyle(.secondary)
                        RecordExportButton(recovery: true)
                    }
                    if let loadError {
                        Text("历史记录暂不可读").font(.headline)
                        Text(loadError).font(.footnote).foregroundStyle(.secondary)
                        Button("重新读取") { reload() }
                        RecordExportButton(recovery: true)
                    } else if records.isEmpty && unreadableCount == 0 {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 48)).foregroundStyle(.purple)
                        Text("暂无测试记录").font(.headline)
                        Text("完成练习或结束并保存已答题后，可在这里查看记录。")
                            .foregroundStyle(.secondary)
                    } else {
                        if unreadableCount > 0 {
                            Text("有 \(unreadableCount) 条记录无法读取，原始数据已保留；其余记录仍可查看。")
                                .font(.footnote).foregroundStyle(.orange)
                            if !hasLegacyBackup { RecordExportButton(recovery: true) }
                        }
                        Picker("模块", selection: $filter.module) {
                            ForEach(HistoryFilter.Module.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("historyModuleFilter")
                        Picker("完成状态", selection: $filter.completion) {
                            ForEach(HistoryFilter.Completion.allCases) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("historyCompletionFilter")
                        HStack(spacing: 12) {
                            summary("当前结果", visible.count)
                            summary("已完成", visible.filter { $0.completion == .completed }.count)
                            summary("提前结束", visible.filter { $0.completion == .endedEarly }.count)
                        }
                        if !visible.isEmpty { RecordExportButton(records: visible) }
                        else { Text("没有符合筛选条件的记录").foregroundStyle(.secondary) }
                        if visibleQuestionSets.count > 1 {
                            Text("本页包含 \(visibleQuestionSets.map(\.title).joined(separator: "、")) 的记录。两组题目不同且尚未等值，分数不能直接比较，也不能据此判断哪一题组更难。")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Text("IQ 估算尚未校准，不同题库、模型或难度的结果不合并为能力趋势。")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(visible) { record in
                            NavigationLink {
                                TestRecordDetailView(record: record, onDeleted: reload, keepsLegacyBackup: hasLegacyBackup)
                            } label: {
                                row(record)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("historyRecord")
                        }
                    }
                }.padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("历史成绩").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空", role: .destructive) { showClearConfirm = true }
                        .disabled(records.isEmpty && loadError == nil && unreadableCount == 0 && !hasLegacyBackup)
                }
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .onAppear { reload() }
            .refreshable { reload() }
            .confirmationDialog("确定清空全部历史记录及原始备份吗？此操作不受当前筛选影响。", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空所有历史和备份", role: .destructive) {
                    do { try RecordStore.clear(); reload() }
                    catch { reload(); operationError = error.localizedDescription }
                }
                Button("取消", role: .cancel) {}
            }
            .alert("操作未完成", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
                Button("好") { operationError = nil }
            } message: { Text(operationError ?? "") }
        }
    }

    private func reload() {
        do {
            let snapshot = try RecordStore.read()
            records = snapshot.records
            unreadableCount = snapshot.unreadableCount
            hasLegacyBackup = snapshot.hasLegacyBackup
            loadError = nil
        } catch {
            records = []
            loadError = error.localizedDescription
        }
    }

    private func summary(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 6) {
            Text("\(value)").font(.title2.bold()).foregroundStyle(.purple)
                .accessibilityIdentifier("historySummary-\(title)")
            Text(title).font(.caption)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ record: TestRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: record.testType.systemImage)
                .font(.title3).foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.testType.title).font(.headline)
                if let set = record.questionSet { Text(set.title).font(.caption.bold()) }
                Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                let age = record.age.map { "\($0) 岁 · " } ?? ""
                let isLegacyWechsler = record.testType == .wechsler && record.scoringVersion == nil
                Text(age + (isLegacyWechsler
                            ? "旧版记录 · 原始分 \(record.score)/\(record.total)"
                            : record.detail ?? "\(record.difficulty.rawValue) · 原始分 \(record.score)/\(record.total)"))
                    .font(.caption).foregroundStyle(.secondary)
                if record.completion == .endedEarly {
                    Text("提前结束 · 未生成 IQ 估算").font(.caption).foregroundStyle(.secondary)
                } else if let administration = record.administration, !administration.interruptions.isEmpty {
                    Text("中断 \(administration.interruptions.count) 题 · 未生成 IQ 估算")
                        .font(.caption).foregroundStyle(.secondary)
                } else if record.iq != nil && record.estimateValue == nil {
                    Text("旧版估算不作 IQ 解释").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                if let value = record.profileValue ?? record.estimateValue {
                    Text("\(value)").font(.title2.bold()).foregroundStyle(.purple)
                    Text(record.wechslerProfile == nil ? "估算 IQ · 未校准" : "全量表分 · 未校准")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("\(record.score)/\(record.total)").font(.subheadline.bold())
                Text("原始分").font(.caption2).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
