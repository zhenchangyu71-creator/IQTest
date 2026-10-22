import Foundation

/// 自编操作示例与计分题库分开，旨在确认操作理解，不测量能力。
struct WechslerInstructions {
    let guidance: String
    let sample: WechslerItem

    static let protocolVersion = "self-guided-2026-10-21-v1"

    static func forSubtest(_ subtest: WechslerSubtest) -> Self {
        let guidance: String
        let prompt: String
        let options: [String]
        let explanation: String
        switch subtest {
        case .block:
            guidance = "阅读图形或空间关系，从选项中选择最符合要求的一项。本应用采用文字和符号题。"
            prompt = "示例：两块大小相同的正方形左右紧贴，组合后的外轮廓是什么？"
            options = ["长方形", "三角形", "圆形"]
            explanation = "两个正方形左右相接，外轮廓是长方形。点击选项即可提交。"
        case .similarities:
            guidance = "选择能概括两种事物共同特征的答案。正式题按答案完整程度给 0、1 或 2 分。"
            prompt = "示例：报纸和杂志有什么共同点？"
            options = ["都是供人阅读的出版物", "都有图片", "都是交通工具"]
            explanation = "“供人阅读的出版物”概括了共同类别，比某个外观特点更完整。"
        case .digitspan:
            guidance = "数字只显示一次，隐藏后输入完整序列。顺序＝原顺序；逆序＝从后往前；升序＝从小到大。无需用空格分隔，不使用纸笔记录。"
            prompt = "输入示例（不计时）：看到 5 2 8，若要求【升序】，请在下方输入 258。"
            options = ["258", "528", "825"]
            explanation = "升序是从小到大。正式题请留意每题要求，输入完整数字后点击提交。"
        case .matrix:
            guidance = "观察符号的排列或变化规律，选择能补全空缺的一项。"
            prompt = "示例：○ △ ○ △ ○ ？空缺处应是什么？"
            options = ["△", "○", "□"]
            explanation = "圆形与三角形交替出现，空缺处应为三角形。"
        case .vocabulary:
            guidance = "选择最准确、完整的词义。正式题按答案完整程度给 0、1 或 2 分。"
            prompt = "示例：“整洁”最接近哪个意思？"
            options = ["整齐而清洁", "非常昂贵", "声音很大"]
            explanation = "“整洁”表示整齐而清洁。点击选项即可提交。"
        case .arithmetic:
            guidance = "读清条件后进行心算，选择计算结果。不使用计算器或纸笔。"
            prompt = "示例：每盒有 3 支铅笔，2 盒共有多少支？"
            options = ["6 支", "5 支", "3 支"]
            explanation = "3 × 2 = 6。点击结果即可提交。"
        case .symbolsearch:
            guidance = "快速核对目标符号是否出现在给定符号行中。每题只有 5 秒，先熟悉操作再开始。"
            prompt = "示例：目标是 ◆。符号行为 ○ △ ◆ □，目标是否出现？"
            options = ["出现", "未出现"]
            explanation = "符号行中有 ◆，所以选择“出现”。本示例不计时。"
        case .visualpuzzle:
            guidance = "根据形状分割或组合关系选择答案。本应用采用文字和符号题。"
            prompt = "操作示例：请点击选项中的【正方形 □】。"
            options = ["正方形 □", "圆形 ○", "三角形 △"]
            explanation = "看到符号后点击对应选项即可。计分题将要求判断图形的分割或组合关系。"
        case .information:
            guidance = "依据已有知识选择最准确的答案，不查询资料。正式题可有部分得分选项。"
            prompt = "示例：一天有多少小时？"
            options = ["24 小时", "12 小时", "60 小时"]
            explanation = "一天有 24 小时。点击选项即可提交。"
        case .coding:
            guidance = "按每题给出的符号与数字对照表，选择对应序列。每题只有 5 秒，注意符号顺序。"
            prompt = "示例：○＝4，□＝7。那么 ○ □ 对应什么？"
            options = ["47", "74", "44"]
            explanation = "先 ○ 后 □，依次对应 4 和 7，因此是 47。本示例不计时。"
        }
        return Self(guidance: guidance, sample: WechslerItem(
            id: "tutorial-\(subtest.id)", subtest: subtest, prompt: prompt, options: options,
            optionScores: options.indices.map { $0 == 0 ? subtest.maxPointsPerItem : 0 },
            explanation: explanation, presentation: subtest == .digitspan ? "digits" : nil,
            stimulus: subtest == .digitspan ? "5 2 8" : nil,
            displaySeconds: subtest == .digitspan ? 4 : nil,
            recallRule: subtest == .digitspan ? .ascending : nil))
    }
}
