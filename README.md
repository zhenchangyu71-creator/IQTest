# 智商测试（IQTest）

SwiftUI 智商测试应用，iOS 17+，XcodeGen 管理工程。内含两套并存题库：

- **瑞文推理**：图形矩阵与逻辑推理，四种题型 × 三种难度，每轮随机抽 12 题
- **韦氏标准流程**：10 个分测验、120 个项目，按 WAIS 施测顺序与停测规则施测

> 本应用所有计分均为简化娱乐模型，不等同于专业心理测评。

## 目录结构

```
IQTest/
├── IQTestApp.swift          # @main + ContentView（按 phase 切换页面）
├── Models/
│   ├── Question.swift       # 瑞文题目模型 + TestType/Difficulty/QuestionCategory
│   ├── Wechsler.swift       # 韦氏题目模型 + WechslerSubtest/Domain + 简化常模计分
│   ├── AgeBand.swift        # 年龄带（6–12/13–17/18–59/60+）与年龄常模校准
│   └── TestRecord.swift     # 历史记录（Codable，旧记录缺字段兼容解码）
├── Services/
│   └── QuestionLoader.swift # 题库 JSON 加载
├── ViewModels/
│   ├── QuizViewModel.swift       # 瑞文流程
│   ├── WechslerViewModel.swift   # 韦氏标准流程
│   └── PracticeViewModel.swift   # 分测验练习模式（含 PracticeStore 成绩持久化）
├── Views/
│   ├── WelcomeView.swift        # 首页（体系选择 / 年龄输入 / 难度 / 练习入口）
│   ├── QuizView.swift / ResultView.swift          # 瑞文答题 / 结果
│   ├── WechslerQuizView.swift / WechslerResultView.swift  # 韦氏答题 / 结果
│   ├── SubtestPracticeView.swift # 分测验练习（选择 → 答题 → 结果）
│   ├── PracticeRadarView.swift   # 自绘十轴雷达图（本次 vs 练习最佳叠加）
│   └── HistoryView.swift         # 历史成绩（趋势图 + 记录列表）
└── Resources/
    ├── Questions.json     # 瑞文题库：144 题（4 类 × 3 难度 × 12）
    └── Wechsler.json      # 韦氏题库：120 题（10 分测验 × 12）
project.yml                # XcodeGen 工程描述（部署目标 iOS 17.0）
```

## 核心机制

### 双流程切换（ContentView）

`WechslerViewModel.phase != .idle` 时显示韦氏答题/结果页，否则按 `QuizViewModel.phase` 显示首页/瑞文答题/结果。韦氏"返回首页"调用 `reset()` 回到 idle。

### 瑞文计分

每轮从所选难度池中按类别随机抽 3 题（共 12 题）。估算 IQ = 100 + (得分率 − 期望得分率) / 0.20 × 15， clamp 到 55–145。期望得分率按难度（初级 0.70 / 中级 0.55 / 高级 0.40）加 `AgeBand.ravenMeanOffset` 校准。

### 韦氏标准流程

- 10 分测验按 `WechslerSubtest.allCases` 顺序施测，分测验内按文件顺序（难度递增）
- 同一分测验连续 3 题得 0 分提前进入下一分测验（停测规则）
- 数字广度（digitspan）题目带 `presentation: "digits"`，先呈现刺激 `displaySeconds` 秒再作答
- 言语类分测验（类同/词汇/常识）按 0/1/2 计分，其余 0/1 计分
- 量表分 = 10 + (原始分/满分 − 0.5) × 12，clamp 1–19，再加年龄校准偏移
- 指数 = 100 + (平均分测验量表分 − 10) × 5；FSIQ 为全部分测验量表分均值代入同一公式

### 年龄常模（AgeBand）

首页输入 6–99 岁，持久化到 UserDefaults（键 `testTakerAge`，默认 25）。四个年龄带：儿童 6–12 / 青少年 13–17 / 成人 18–59 / 老年 60+。这是**简化年龄常模**（真实韦氏按具体岁数查常模表），结果页会明示所用年龄带。

### 分测验练习模式

首页选韦氏体系后出现"单项训练"入口。每组分层抽取 3 题（题库易/中/难三段各 1 题），答题体验与标准施测一致。结果给出估计量表分（按本组满分归一 + 年龄校准），并持久化每个分测验的练习次数与最佳分（UserDefaults 键 `wechslerPracticeStats`）。练习成绩不计入测试历史。

### 雷达图（PracticeRadarView）

自绘十轴雷达（Canvas），兼容 iOS 17（系统的 RadarChart 需 iOS 18）。支持双序列叠加：紫色实线主序列、橙色虚线对比序列。练习选择页显示各分测验最佳分；韦氏结果页显示本次测验 vs 练习最佳。

## 题库数据格式

### Questions.json（瑞文）

```json
{
  "id": 97,                      // 全局唯一，当前 1–144
  "difficulty": "easy",          // easy / medium / hard
  "category": "number",          // number / verbal / logic / pattern
  "prompt": "数列：3，6，9，12，？",
  "options": ["14", "15", "16", "18"],
  "correctIndex": 1,
  "explanation": "公差为 3 的等差数列，12 + 3 = 15。"
}
```

### Wechsler.json（韦氏）

```json
{
  "subtest": "digitspan",        // 英文键（自定义 init(from:) 同时兼容中文 rawValue）
  "prompt": "请记住下面的数字……",
  "options": ["3 9 1", "1 9 3", "…"],
  "optionScores": [1, 0, 0, 0],  // 与 options 一一对应，0/1/2
  "presentation": "digits",      // 可选：数字广度先呈现刺激
  "stimulus": "3 9 1",           // 可选：刺激内容
  "displaySeconds": 4            // 可选：刺激呈现秒数
}
```

文件内题目按分测验分组、组内按难度递增排列；`WechslerLoader` 按文件顺序填充 `order`。新增题目追加在对应分测验组末尾即可。

## 构建与测试

```bash
# 工程由 XcodeGen 生成：新增/删除/重命名源文件后必须重跑
USER=$(id -un) xcodegen

# 构建（模拟器）
xcodebuild -project IQTest.xcodeproj -scheme IQTest \
  -destination 'platform=iOS Simulator,id=<模拟器ID>' build

# 安装到模拟器
xcrun simctl install <模拟器ID> \
  ~/Library/Developer/Xcode/DerivedData/IQTest-*/Build/Products/Debug-iphonesimulator/IQTest.app
```

UI 测试使用 /tmp/iqtest_verify/uitest 下的独立 harness 工程（xcodegen 项目，DummyHost + XCUITest target），以黑盒方式驱动已安装的 app（bundle id `com.iqtest.IQTest`）：

```bash
cd /tmp/iqtest_verify/uitest && USER=$(id -un) xcodebuild test \
  -project UITestHarness.xcodeproj -scheme UITestHarness \
  -destination 'platform=iOS Simulator,id=<模拟器ID>'
```

现有用例：`testRavenFlow`（瑞文 + 年龄输入）、`testWechslerFlow`（韦氏全流程 + 结果雷达图）、`testPracticeFlow`（练习模式 + 雷达图统计）。

## 已知坑（血泪经验）

1. **枚举用中文 rawValue 时**，JSON 里的英文键必须写自定义 `init(from:)` 做双向兼容（`WechslerSubtest`、`TestType`、`Difficulty` 均如此）。
2. **自定义 `init(from:)` 会吞掉成员初始化器**，需要手动补回（`TestRecord`、`WechslerItem` 已补）。新增可选字段用 `decodeIfPresent` 保持旧数据兼容。
3. **swiftc 单文件脚本校验**（不进模拟器快速验证 JSON/计分）：入口文件必须叫 `main.swift`，且目录里不能有第二个含顶层代码的文件。
4. **UI 测试点步进器**：iOS 的 `XCUIElement` 没有 `decrementButton`，用 `coordinate(withNormalizedOffset:)` 点减号一侧（dx 0.05）/加号一侧（dx 0.95）。
5. **卡片类按钮**的可访问性标签是"标题+副标题"拼接，匹配要用 `label CONTAINS`。
6. 年龄、练习成绩存在 UserDefaults，**UI 测试不能假定默认值**，先读当前值再调整（见 testRavenFlow）。
7. 每次重跑 `xcodegen` 会重新生成 `.xcodeproj`，不要在工程文件里手改设置——改 `project.yml`。
