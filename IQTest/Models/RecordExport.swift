import Foundation

/// 面向用户导出的文件格式；不在导出时重算任何成绩。
struct RecordExport: Codable {
    let formatVersion: Int
    let exportedAt: Date
    let notice: String
    let records: [TestRecord]

    static func encode(_ records: [TestRecord], at date: Date = Date()) throws -> Data {
        let envelope = Self(formatVersion: 1, exportedAt: date,
                            notice: "包含原始成绩、未校准估算与量表分剖面（wechslerProfile：尺度分、指数分、全量表分、百分位与区间）。旧 iq/percentile 字段仅为保留档案，不代表有效标准分；量表分未经人群常模校准，不是正式韦氏 IQ。A/B 题组未等值。",
                            records: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }
}
