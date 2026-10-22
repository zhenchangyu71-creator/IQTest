import Foundation

struct TestRecord: Codable, Identifiable {
    enum Completion: String, Codable { case completed, endedEarly }
    var id = UUID()
    let date: Date
    let testType: TestType
    let difficulty: Difficulty
    let score: Int
    let total: Int
    let iq: Int?
    let percentile: Int?
    /// 附加摘要（韦氏新版保存领域原始分，不含标准指数）
    let detail: String?
    /// 被试年龄（旧记录无此字段）
    let age: Int?

    let scoringVersion: String?
    let responses: [WechslerResponse]?
    /// 未校准的模型结果，与正式 IQ 字段分开保存，不进入瑞文趋势。
    let iqEstimate: WechslerIQEstimate?
    /// 韦氏风格的量表分剖面，与正式 IQ 字段分开保存。
    let wechslerProfile: WechslerProfile?
    let administration: WechslerAdministration?
    let ravenEstimate: RavenIQEstimate?
    let reviewItems: [RecordedItem]?
    let completion: Completion
    let plannedItemCount: Int?
    let questionSet: WechslerQuestionSet?
    /// 旧经验公式记录原样保留，不能继续当成人群标准分展示。
    var displayedIQ: Int? { completion == .completed && testType == .raven ? ravenEstimate?.value : nil }
    var estimateValue: Int? {
        guard completion == .completed else { return nil }
        return testType == .raven ? ravenEstimate?.value : iqEstimate?.value
    }
    /// 韦氏风格剖面给出的全量表分。旧记录没有该字段时回落到实验性估算。
    var profileValue: Int? {
        guard completion == .completed, testType == .wechsler else { return nil }
        return wechslerProfile?.fullScale.score ?? iqEstimate?.value
    }

    init(date: Date, testType: TestType, difficulty: Difficulty,
         score: Int, total: Int, iq: Int?, percentile: Int?,
         detail: String? = nil, age: Int? = nil,
         scoringVersion: String? = nil, responses: [WechslerResponse]? = nil,
         iqEstimate: WechslerIQEstimate? = nil, wechslerProfile: WechslerProfile? = nil,
         administration: WechslerAdministration? = nil,
         ravenEstimate: RavenIQEstimate? = nil, reviewItems: [RecordedItem]? = nil,
         completion: Completion = .completed, plannedItemCount: Int? = nil,
         questionSet: WechslerQuestionSet? = nil) {
        self.date = date
        self.testType = testType
        self.difficulty = difficulty
        self.score = score
        self.total = total
        self.iq = iq
        self.percentile = percentile
        self.detail = detail
        self.age = age
        self.scoringVersion = scoringVersion
        self.responses = responses
        self.iqEstimate = iqEstimate
        self.wechslerProfile = wechslerProfile
        self.administration = administration
        self.ravenEstimate = ravenEstimate
        self.reviewItems = reviewItems
        self.completion = completion
        self.plannedItemCount = plannedItemCount
        self.questionSet = questionSet
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
        iq = try container.decodeIfPresent(Int.self, forKey: .iq)
        percentile = try container.decodeIfPresent(Int.self, forKey: .percentile)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        age = try container.decodeIfPresent(Int.self, forKey: .age)
        scoringVersion = try container.decodeIfPresent(String.self, forKey: .scoringVersion)
        responses = try container.decodeIfPresent([WechslerResponse].self, forKey: .responses)
        iqEstimate = try container.decodeIfPresent(WechslerIQEstimate.self, forKey: .iqEstimate)
        wechslerProfile = try container.decodeIfPresent(WechslerProfile.self, forKey: .wechslerProfile)
        administration = try container.decodeIfPresent(WechslerAdministration.self, forKey: .administration)
        ravenEstimate = try container.decodeIfPresent(RavenIQEstimate.self, forKey: .ravenEstimate)
        reviewItems = try container.decodeIfPresent([RecordedItem].self, forKey: .reviewItems)
        completion = try container.decodeIfPresent(Completion.self, forKey: .completion) ?? .completed
        plannedItemCount = try container.decodeIfPresent(Int.self, forKey: .plannedItemCount)
        questionSet = try container.decodeIfPresent(WechslerQuestionSet.self, forKey: .questionSet)
    }
}
