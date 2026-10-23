import XCTest

final class StartQuizUITest: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testEndingRavenSavesPartialHistoryWithDetailsAndNoIQ() throws {
        let app = XCUIApplication(bundleIdentifier: "com.iqtest.IQTest")
        app.launch()
        app.buttons["开始瑞文中级测试"].tap()
        let end = app.buttons["endSession"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "ravenOption").firstMatch.tap()
        end.tap()
        XCTAssertTrue(app.staticTexts["本次练习提前结束"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["experimentalRavenIQValue"].exists)
        let home = app.buttons["返回首页"]
        reveal(home, app: app)
        home.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS '历史成绩'")).firstMatch.tap()
        app.buttons.matching(identifier: "historyRecord").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["记录详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["未完成 · 不生成 IQ 估算"].exists)
        let review = app.buttons.matching(NSPredicate(format: "label CONTAINS '逐题记录'")).firstMatch
        reveal(review, app: app)
        review.tap()
        XCTAssertTrue(app.staticTexts["recordedPrompt"].firstMatch.exists)
    }

    func testEndingWechslerSavesPartialHistoryWithoutUnseenAnswers() throws {
        let app = XCUIApplication(bundleIdentifier: "com.iqtest.IQTest")
        app.launch()
        selectWechsler(app: app)
        let start = app.buttons["开始韦氏完整练习"]
        reveal(start, app: app)
        start.tap()
        completeTutorial(app: app)
        app.buttons.matching(identifier: "wechslerOption").firstMatch.tap()
        app.buttons["endSession"].tap()
        XCTAssertTrue(app.staticTexts["本次练习提前结束"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["experimentalIQValue"].exists)
        let home = app.buttons["返回首页"]
        reveal(home, app: app)
        home.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS '历史成绩'")).firstMatch.tap()
        app.buttons.matching(identifier: "historyRecord").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["记录详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["未完成 · 不生成 IQ 估算"].exists)
        XCTAssertTrue(app.staticTexts["已记录 1/120 题"].exists)
    }

    func testQuestionSetBCanBeSelectedAndItsIdentitySurvivesHistory() throws {
        let app = XCUIApplication(bundleIdentifier: "com.iqtest.IQTest")
        app.launch()
        selectWechsler(app: app)
        let setB = app.buttons["题组 B"]
        reveal(setB, app: app)
        setB.tap()
        let start = app.buttons["开始韦氏完整练习"]
        reveal(start, app: app)
        start.tap()
        completeTutorial(app: app)
        // 首题具体是哪一道取决于抽题轮换，这里只校验分测验与题量恒定。
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '第 1 / 12 题'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '积木'")).firstMatch.exists)
        app.buttons.matching(identifier: "wechslerOption").firstMatch.tap()
        app.buttons["endSession"].tap()
        XCTAssertTrue(app.staticTexts["题组 B · 题组尚未等值"].waitForExistence(timeout: 5))
        let restart = app.buttons["再练一次"]
        reveal(restart, app: app)
        restart.tap()
        completeTutorial(app: app)
        // 重练时抽题优先取没做过的题，首题未必与第一轮相同：
        // 题组归属由结果页的题组标识确认，这里只校验仍在出题且题量恒定。
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '第 1 / 12 题'")).firstMatch.exists,
                      "B 组重练应继续使用 B 组")
        app.buttons.matching(identifier: "wechslerOption").firstMatch.tap()
        app.buttons["endSession"].tap()
        XCTAssertTrue(app.staticTexts["题组 B · 题组尚未等值"].waitForExistence(timeout: 5))
        let home = app.buttons["返回首页"]
        reveal(home, app: app)
        home.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS '历史成绩'")).firstMatch.tap()
        app.buttons.matching(identifier: "historyRecord").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["记录详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["题组 B · 题组尚未等值"].exists)
    }

    func testHistoryFiltersExportsAndRemovesOnlyOneRecord() throws {
        let app = XCUIApplication(bundleIdentifier: "com.iqtest.IQTest")
        app.launch()
        app.buttons["开始瑞文中级测试"].tap()
        app.buttons.matching(identifier: "ravenOption").firstMatch.tap()
        app.buttons["endSession"].tap()
        let home = app.buttons["返回首页"]
        reveal(home, app: app)
        home.tap()
        selectWechsler(app: app)
        let start = app.buttons["开始韦氏完整练习"]
        reveal(start, app: app)
        start.tap()
        completeTutorial(app: app)
        app.buttons.matching(identifier: "wechslerOption").firstMatch.tap()
        app.buttons["endSession"].tap()
        reveal(home, app: app)
        home.tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS '历史成绩'")).firstMatch.tap()
        let ravenFilter = app.buttons["推理"]
        XCTAssertTrue(ravenFilter.waitForExistence(timeout: 5))
        ravenFilter.tap()
        app.buttons["提前结束"].tap()
        let count = app.staticTexts["historySummary-当前结果"]
        let before = try XCTUnwrap(Int(count.label))
        XCTAssertGreaterThan(before, 0)
        app.buttons.matching(identifier: "historyRecord").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["记录详情"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["瑞文推理"].exists)
        XCTAssertTrue(app.staticTexts["未完成 · 不生成 IQ 估算"].exists)
        let export = try XCTUnwrap(app.buttons.matching(identifier: "exportRecords").allElementsBoundByIndex.first { $0.isHittable })
        export.tap()
        let filename = app.textFields["DOCPicker.filenameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 8))
        let marker = UUID().uuidString
        filename.tap()
        filename.typeText("-" + marker)
        XCTAssertTrue((filename.value as? String)?.contains(marker) ?? false)
        app.buttons.matching(NSPredicate(format: "label IN {'保存', 'Save'}")).firstMatch.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: filename)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
        XCTAssertTrue(app.navigationBars["记录详情"].waitForExistence(timeout: 5))
        app.buttons["记录操作"].tap()
        app.buttons["从历史移除"].tap()
        app.buttons["确认移除"].tap()
        XCTAssertTrue(app.navigationBars["历史成绩"].waitForExistence(timeout: 5))
        XCTAssertEqual(Int(count.label), before - 1)
        app.buttons["韦氏"].tap()
        app.buttons.matching(identifier: "historyRecord").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["韦氏风格练习"].waitForExistence(timeout: 5))
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
            let options = app.buttons.matching(identifier: "ravenOption").allElementsBoundByIndex.filter { $0.isHittable }
            XCTAssertFalse(options.isEmpty, "\(startButtonLabel)：第 \(i) 题没有可点击的选项")
            options[0].tap()
            if i < 12 { sleep(2) }
        }

        sleep(3)
        XCTAssertTrue(app.staticTexts["实验性 IQ 估算"].waitForExistence(timeout: 10),
                      "\(startButtonLabel)：答完后未进入结果页")
        XCTAssertTrue(app.staticTexts["未校准 · 年龄仅作记录、未参与换算"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '超过全球'")).firstMatch.exists)
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

    // MARK: - 韦氏自编练习

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 {
            if element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "控件不可见：\(element.label)")
    }

    private func selectWechsler(app: XCUIApplication) {
        let card = app.buttons.matching(NSPredicate(format: "label CONTAINS '韦氏风格练习'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
    }

    private func completeTutorial(app: XCUIApplication) {
        let begin = app.buttons["startSubtest"]
        XCTAssertTrue(begin.waitForExistence(timeout: 5))
        XCTAssertFalse(begin.isEnabled)
        let recall = app.textFields["tutorialRecallInput"]
        if recall.exists {
            reveal(recall, app: app)
            recall.tap()
            recall.typeText("258")
            let check = app.buttons["submitTutorial"]
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: check)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
            check.tap()
        } else {
            let sample = app.buttons.matching(identifier: "tutorialOption").firstMatch
            reveal(sample, app: app)
            sample.tap()
        }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: begin)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
        begin.tap()
    }

    private func answerUntilResult(app: XCUIApplication, title: String, limit: Int) {
        let result = app.staticTexts[title]
        var iterations = 0
        while !result.exists && iterations < limit {
            iterations += 1
            let input = app.textFields["digitRecallInput"]
            let option = app.buttons.matching(identifier: "wechslerOption").firstMatch
            if app.buttons["startSubtest"].exists {
                completeTutorial(app: app)
            } else if input.exists {
                input.typeText("0")
                let submit = app.buttons["提交回忆"]
                let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: submit)
                XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 3), .completed)
                submit.tap()
            } else if option.exists && option.isHittable {
                option.tap()
            } else {
                // 刺激阶段不给选项或输入框，等待计时切换。
                Thread.sleep(forTimeInterval: 1)
            }
        }
        XCTAssertTrue(result.waitForExistence(timeout: 5), "答题流程未结束")
    }

    func testWechslerFlow() throws {
        let app = XCUIApplication(bundleIdentifier: "com.iqtest.IQTest")
        app.launch()
        selectWechsler(app: app)
        let start = app.buttons["开始韦氏完整练习"]
        reveal(start, app: app)
        start.tap()
        answerUntilResult(app: app, title: "本次练习报告", limit: 220)
        XCTAssertTrue(app.staticTexts["韦氏风格量表分"].exists)
        XCTAssertTrue(app.staticTexts["profileFullScaleScore"].exists)
        XCTAssertTrue(app.staticTexts["年龄仅作记录、未参与换算 · 不等同正式韦氏 IQ"].exists)
        XCTAssertFalse(app.staticTexts["全量表智商"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '记录 120/120 题'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["领域原始分"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["分测验得分率"].exists)
        let home = app.buttons["返回首页"]
        reveal(home, app: app)
        home.tap()
        let history = app.buttons.matching(NSPredicate(format: "label CONTAINS '历史成绩'")).firstMatch
        reveal(history, app: app)
        history.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '言语'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["全量表分 · 未校准"].exists)
        XCTAssertEqual(app.state, .runningForeground)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "原始分历史记录"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPracticeFlow() throws {
        let app = XCUIApplication(bundleIdentifier: "com.iqtest.IQTest")
        app.launch()
        selectWechsler(app: app)
        let practice = app.buttons["分测验练习"]
        reveal(practice, app: app)
        practice.tap()
        let block = app.buttons["积木 分测验"]
        reveal(block, app: app)
        block.tap()
        answerUntilResult(app: app, title: "本组题目得分率", limit: 10)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '原始分'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '估计量表分'")).firstMatch.exists)
        let other = app.buttons["选择其他分测验"]
        reveal(other, app: app)
        other.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '已练'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testDigitRecallHidesChoicesAndOffersInputAfterStimulus() throws {
        let app = XCUIApplication(bundleIdentifier: "com.iqtest.IQTest")
        app.launch()
        selectWechsler(app: app)
        let practice = app.buttons["分测验练习"]
        reveal(practice, app: app)
        practice.tap()
        let digits = app.buttons["数字广度 分测验"]
        reveal(digits, app: app)
        digits.tap()
        completeTutorial(app: app)
        XCTAssertFalse(app.buttons.matching(identifier: "wechslerOption").firstMatch.exists)
        let input = app.textFields["digitRecallInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 12))
        XCTAssertFalse(app.buttons.matching(identifier: "wechslerOption").firstMatch.exists)
        XCTAssertFalse(app.buttons["提交回忆"].isEnabled)
        input.typeText("0")
        XCTAssertEqual(input.value as? String, "0", app.debugDescription)
        let submit = app.buttons["提交回忆"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: submit)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 3), .completed)
        submit.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '第 2 / 3 题'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["关闭"].tap()
    }

    func testInterruptionWaitsForAcknowledgementBeforeNextItem() throws {
        let app = XCUIApplication(bundleIdentifier: "com.iqtest.IQTest")
        app.launch()
        selectWechsler(app: app)
        let practice = app.buttons["分测验练习"]
        reveal(practice, app: app)
        practice.tap()
        let block = app.buttons["积木 分测验"]
        reveal(block, app: app)
        block.tap()
        completeTutorial(app: app)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["练习已中断"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(identifier: "wechslerOption").firstMatch.exists)
        app.buttons["继续下一题"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '第 2 / 3 题'")).firstMatch.waitForExistence(timeout: 5))
        answerUntilResult(app: app, title: "本组题目得分率", limit: 5)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '中断 1 题'")).firstMatch.exists)
        app.buttons["关闭"].tap()
    }
}
