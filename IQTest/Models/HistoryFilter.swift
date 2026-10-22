import Foundation

struct HistoryFilter {
    enum Module: String, CaseIterable, Identifiable {
        case all = "全部模块", raven = "推理", wechsler = "韦氏"
        var id: String { rawValue }
    }
    enum Completion: String, CaseIterable, Identifiable {
        case all = "全部状态", completed = "已完成", endedEarly = "提前结束"
        var id: String { rawValue }
    }
    var module: Module = .all
    var completion: Completion = .all

    func apply(to records: [TestRecord]) -> [TestRecord] {
        records.filter { record in
            (module == .all || (module == .raven ? record.testType == .raven : record.testType == .wechsler))
            && (completion == .all || (completion == .completed ? record.completion == .completed : record.completion == .endedEarly))
        }.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
    }
}
