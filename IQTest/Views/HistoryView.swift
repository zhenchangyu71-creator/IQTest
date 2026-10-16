import SwiftUI
import Charts

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [TestRecord] = []
    @State private var showClearConfirm = false

    private var averageIQ: Int {
        guard !records.isEmpty else { return 0 }
        return Int((Double(records.map(\.iq).reduce(0, +)) / Double(records.count)).rounded())
    }

    private var maxIQ: Int { records.map(\.iq).max() ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if records.isEmpty {
                        emptyState
                    } else {
                        summaryCards
                        chartSection
                        recordList
                        Button("清空历史记录", role: .destructive) {
                            showClearConfirm = true
                        }
                        .font(.footnote)
                        .padding(.bottom, 20)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("历史成绩")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { records = RecordStore.load().reversed() }
            .confirmationDialog("确定清空所有历史记录吗？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    RecordStore.clear()
                    records = []
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 80)
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 56))
                .foregroundStyle(.purple)
            Text("暂无测试记录")
                .font(.headline)
            Text("完成一次智商测试后，\n这里会展示你的成绩趋势。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - 汇总卡片

    private var summaryCards: some View {
        HStack(spacing: 12) {
            SummaryCard(title: "测试次数", value: "\(records.count)", icon: "list.number", color: .purple)
            SummaryCard(title: "平均 IQ", value: "\(averageIQ)", icon: "brain.head.profile", color: .indigo)
            SummaryCard(title: "最高 IQ", value: "\(maxIQ)", icon: "trophy.fill", color: .orange)
        }
    }

    // MARK: - 趋势图

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("IQ 趋势")
                .font(.headline)
            let ordered = records.reversed() // 时间正序
            Chart {
                RuleMark(y: .value("平均", 100))
                    .lineStyle(StrokeStyle(dash: [5, 5]))
                    .foregroundStyle(.secondary.opacity(0.5))
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, record in
                    LineMark(
                        x: .value("次数", index + 1),
                        y: .value("IQ", record.iq)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.purple)
                    PointMark(
                        x: .value("次数", index + 1),
                        y: .value("IQ", record.iq)
                    )
                    .foregroundStyle(.purple)
                    .annotation(position: .top) {
                        Text("\(record.iq)")
                            .font(.caption2.bold())
                            .foregroundStyle(.purple)
                    }
                }
            }
            .chartYScale(domain: 55...145)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: min(records.count, 6))) { _ in
                    AxisValueLabel()
                }
            }
            .frame(height: 180)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 记录列表

    private var recordList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("测试记录")
                .font(.headline)
            ForEach(records) { record in
                let agePrefix = record.age.map { "\($0) 岁 · " } ?? ""
                HStack(spacing: 12) {
                    Image(systemName: record.testType.systemImage)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(difficultyColor(record.difficulty), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.dateFormatter.string(from: record.date))
                            .font(.subheadline.bold())
                        if let detail = record.detail {
                            Text(agePrefix + detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(agePrefix + "\(record.difficulty.rawValue) · 答对 \(record.score)/\(record.total) · 超 \(record.percentile)% 的人")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(record.iq)")
                            .font(.title3.bold())
                            .foregroundStyle(.purple)
                        Text("IQ")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private func difficultyColor(_ level: Difficulty) -> Color {
        switch level {
        case .easy: return .green
        case .medium: return .orange
        case .hard: return .red
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color, in: RoundedRectangle(cornerRadius: 8))
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HistoryView()
}
