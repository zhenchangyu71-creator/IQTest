import XCTest

final class StartQuizUITest: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 瑞文流程

    private func runFullQuiz(app: XCUIApplication, startButtonLabel: String) {
        let startButton = app.buttons[startButtonLabel]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "未找到按钮 \(startButtonLabel)")
        startButton.tap()

        let predicate = NSPredicate(format: "label CONTAINS '第'")
        let header = app.staticTexts.containing(predicate).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10), "\(startButtonLabel)：答题界面未出现")
        XCTAssertTrue(header.label.contains("12"), "\(startButtonLabel)：本轮应为 12 题，实际：\(header.label)")

        for i in 1...12 {
            let options = app.buttons.allElementsBoundByIndex.filter { $0.isHittable }
            XCTAssertFalse(options.isEmpty, "\(startButtonLabel)：第 \(i) 题没有可点击的选项")
            options[0].tap()
            if i < 12 { sleep(2) }
        }

        sleep(3)
        XCTAssertTrue(app.staticTexts["你的估算 IQ"].waitForExistence(timeout: 10),
                      "\(startButtonLabel)：答完后未进入结果页")
        // 结果页应显示所用年龄常模
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '常模'")
        ).firstMatch.waitForExistence(timeout: 5), "结果页未显示常模信息")
        XCTAssertEqual(app.state, .runningForeground)

        let homeButton = app.buttons["返回首页"]
        XCTAssertTrue(homeButton.waitForExistence(timeout: 5))
        homeButton.tap()
        sleep(1)
    }

    func testRavenFlow() throws {
        let app = XCUIApplication(bundleIdentifier: "com.iqtest.IQTest")
        app.launch()

        // 首页应有被试信息年龄输入（年龄持久化，读取当前值而非假定默认值）
        let ageText = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES '^[0-9]+ 岁$'")
        ).firstMatch
        XCTAssertTrue(ageText.waitForExistence(timeout: 10), "首页未显示年龄")
        let currentAge = Int(ageText.label.dropLast(2)) ?? 25
        let stepper = app.steppers.matching(
            NSPredicate(format: "label CONTAINS '年龄步进器'")
        ).firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 5), "未找到年龄步进器")

        // 调整到 12 岁（儿童带），验证输入生效并跨页面保持
        // 步进器减号位于控件最左端，加号位于最右端
        let minus = stepper.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        let plus = stepper.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        if currentAge > 12 {
            for _ in 1...(currentAge - 12) { minus.tap() }
        } else if currentAge < 12 {
            for _ in 1...(12 - currentAge) { plus.tap() }
        }
        XCTAssertTrue(app.staticTexts["12 岁"].waitForExistence(timeout: 5), "年龄未更新为 12 岁")

        runFullQuiz(app: app, startButtonLabel: "开始瑞文中级测试")

        // 历史记录 caption 应带年龄
        let historyButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '历史成绩'")
        ).firstMatch
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        historyButton.tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '12 岁 ·'")
        ).firstMatch.waitForExistence(timeout: 5), "历史记录中未找到年龄信息")
    }

    // MARK: - 韦氏标准流程

    func testWechslerFlow() throws {
        let app = XCUIApplication(bundleIdentifier: "com.iqtest.IQTest")
        app.launch()

        // 选择韦氏标准体系
        let wechslerCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '韦氏标准'")
        ).firstMatch
        XCTAssertTrue(wechslerCard.waitForExistence(timeout: 10), "未找到韦氏标准选项")
        wechslerCard.tap()
        sleep(1)

        // 开始标准测验
        let startButton = app.buttons["开始韦氏标准测验"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10), "未找到开始韦氏标准测验按钮")
        startButton.tap()

        // 循环作答直至结果页（连续答错会提前结束分测验，总题数不固定）
        let resultTitle = app.staticTexts["全量表智商"]
        var iterations = 0
        while !resultTitle.exists {
            iterations += 1
            XCTAssertLessThan(iterations, 150, "作答循环次数异常，流程可能卡死")
            let options = app.buttons.allElementsBoundByIndex.filter { $0.isHittable }
            if options.isEmpty {
                sleep(2) // 数字广度刺激呈现阶段：无按钮，等待翻页
            } else {
                options[0].tap()
                sleep(2)
            }
        }

        XCTAssertTrue(app.staticTexts["指数分数"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["分测验量表分"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["言语理解指数"].exists)
        XCTAssertTrue(app.staticTexts["分量表雷达图"].exists, "结果页缺少分量表雷达图")
        XCTAssertEqual(app.state, .runningForeground, "应用不在前台运行，可能已经崩溃")

        // 截图留证：FSIQ + 四指数 + 雷达图
        try XCUIScreen.main.screenshot().pngRepresentation.write(
            to: URL(fileURLWithPath: "/tmp/iqtest_verify/wechsler_radar.png"))

        // 返回首页
        let homeButton = app.buttons["返回首页"]
        XCTAssertTrue(homeButton.waitForExistence(timeout: 5))
        homeButton.tap()
        sleep(1)

        // 历史记录里应有韦氏记录（含四指数摘要）
        let historyButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '历史成绩'")
        ).firstMatch
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        historyButton.tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '言语'")
        ).firstMatch.waitForExistence(timeout: 5), "历史记录中未找到韦氏四指数摘要")
    }

    // MARK: - 分测验练习模式

    func testPracticeFlow() throws {
        let app = XCUIApplication(bundleIdentifier: "com.iqtest.IQTest")
        app.launch()

        // 选择韦氏标准体系
        let wechslerCard = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '韦氏标准'")
        ).firstMatch
        XCTAssertTrue(wechslerCard.waitForExistence(timeout: 10))
        wechslerCard.tap()

        // 打开分测验练习
        let practiceButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '分测验练习'")
        ).firstMatch
        XCTAssertTrue(practiceButton.waitForExistence(timeout: 5), "未找到分测验练习入口")
        practiceButton.tap()

        // 选择「积木」分测验
        let blockButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '积木'")
        ).firstMatch
        XCTAssertTrue(blockButton.waitForExistence(timeout: 5), "练习页未显示积木分测验")
        blockButton.tap()

        // 答 3 题（数字广度刺激阶段无按钮，需等待）
        let resultTitle = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '估计量表分'")
        ).firstMatch
        var iterations = 0
        while !resultTitle.exists {
            iterations += 1
            XCTAssertLessThan(iterations, 60, "练习流程可能卡死")
            let options = app.buttons.allElementsBoundByIndex.filter {
                $0.isHittable && !$0.label.contains("关闭")
            }
            if options.isEmpty {
                sleep(2)
            } else {
                options[0].tap()
                sleep(1)
            }
        }

        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '原始分'")
        ).firstMatch.exists, "练习结果缺少原始分")
        XCTAssertTrue(app.buttons["再练一组"].exists)
        XCTAssertTrue(app.buttons["选择其他分测验"].exists)
        XCTAssertEqual(app.state, .runningForeground, "应用不在前台运行，可能已经崩溃")

        // 返回选择页应显示已练习记录与雷达图统计
        app.buttons["选择其他分测验"].tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '练过'")
        ).firstMatch.waitForExistence(timeout: 5), "未记录练习次数")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '已练'")
        ).firstMatch.waitForExistence(timeout: 5), "雷达图未显示练习统计")

        // 截图留证：雷达图 + 练习记录
        try XCUIScreen.main.screenshot().pngRepresentation.write(
            to: URL(fileURLWithPath: "/tmp/iqtest_verify/practice_radar.png"))

        app.buttons["关闭"].tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label MATCHES '^[0-9]+ 岁$'")
        ).firstMatch.waitForExistence(timeout: 5), "关闭练习后未回到首页")
    }
}
