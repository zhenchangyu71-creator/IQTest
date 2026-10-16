import Foundation

struct TestRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let testType: TestType
    let difficulty: Difficulty
    let score: Int
    let total: Int
    let iq: Int
    let percentile: Int
    /// 附加摘要（韦氏模式存四指数，如「言语 112 · 知觉 105」）
    let detail: String?
    /// 被试年龄（旧记录无此字段）
    let age: Int?

    init(date: Date, testType: TestType, difficulty: Difficulty,
         score: Int, total: Int, iq: Int, percentile: Int,
         detail: String? = nil, age: Int? = nil) {
        self.date = date
        self.testType = testType
        self.difficulty = difficulty
        self.score = score
        self.total = total
        self.iq = iq
        self.percentile = percentile
        self.detail = detail
        self.age = age
    }

    /// 旧版记录没有 testType 字段，缺省视为瑞文
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        testType = try container.decodeIfPresent(TestType.self, forKey: .testType) ?? .raven
        difficulty = try container.decode(Difficulty.self, forKey: .difficulty)
        score = try container.decode(Int.self, forKey: .score)
        total = try container.decode(Int.self, forKey: .total)
        iq = try container.decode(Int.self, forKey: .iq)
        percentile = try container.decode(Int.self, forKey: .percentile)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
    }
}

enum RecordStore {
    private static let key = "testRecords"

    static func load() -> [TestRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([TestRecord].self, from: data) else {
            return []
        }
        return records
    }

    static func append(_ record: TestRecord) {
        var records = load()
        records.append(record)
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
