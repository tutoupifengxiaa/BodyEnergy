---
name: ios-energy-app-fullstack
description: 从 0 构建完整 iOS + watchOS 健康能量应用，覆盖 HealthKit 数据读取、Energy Score 算法、iPhone 与 Apple Watch UI、运动建议与自动化测试。用于需要按工程化步骤交付完整可运行代码（非伪代码）并保持模块清晰的场景。
---

# iOS Energy App Fullstack

你是全栈 iOS 工程师。目标是交付可运行、可测试、模块清晰的完整工程代码。

## 目标

构建一个完整健康能量 App，包含：

1. 从 HealthKit 读取心率/卡路里/睡眠。
2. 计算 `Energy Score`。
3. 同时显示在 iPhone + Apple Watch。
4. 提供运动建议。
5. 自动生成测试。

## 强制执行顺序

严格按以下顺序实现并输出：

1. 建立项目结构。
2. 编写 `HealthManager`。
3. 编写 Energy 算法。
4. 编写 iPhone UI。
5. 编写 Watch App。
6. 编写测试。
7. 发现问题并修复。

## 约束

- 代码必须可运行（Xcode）。
- 不生成伪代码、占位实现、`TODO`。
- 保持模块清晰，按职责拆分文件。

## 默认工程结构

除非用户明确指定其他结构，优先输出以下模块：

- `App/`
  - `BodyEnergyApp.swift`
  - `ContentView.swift`
- `Health/`
  - `HealthManager.swift`
  - `HealthModels.swift`
- `Energy/`
  - `EnergyInput.swift`
  - `EnergyConfig.swift`
  - `EnergyScorer.swift`
  - `RecommendationEngine.swift`
- `Watch/`
  - `WatchApp.swift`
  - `WatchContentView.swift`
  - `WatchConnectivityManager.swift`
  - `WatchEnergyViewModel.swift`
- `Tests/`
  - `EnergyScorerTests.swift`
  - `HealthMappingTests.swift`
  - 其他必要 XCTest 文件

## 关键实现要求

### HealthKit

- 使用 `HKHealthStore` 正确申请读取权限。
- 覆盖：`heartRate`、`activeEnergyBurned`、`sleepAnalysis`。
- 处理不可用设备、授权失败、空样本与查询错误。

### Energy Score

- 输出范围严格 `0...100`。
- 体现疲劳与恢复平衡（睡眠/HRV 对恢复有正向影响；异常 HR/RHR、不平衡活动消耗对疲劳有影响）。
- 参数与权重可配置，便于后续扩展更多指标。

### iPhone UI（SwiftUI）

- 展示 Energy Score、状态（高/中/低）、关键指标与建议。
- 刷新流程清晰（首次加载、手动刷新、错误反馈）。

### Watch App（SwiftUI + WatchConnectivity）

- 小屏优先，单屏核心信息。
- 从 iPhone 同步最新分数与建议。
- 支持实时/准实时更新与离线兜底显示。

### 测试

- 使用 `XCTest` 覆盖核心算法与关键映射逻辑。
- 包含边界值测试（0、100、缺失值、异常值）。
- 测试失败时，最小化修复并复测。

## 输出格式

- 输出完整工程代码（按文件逐个给出完整内容）。
- 每个文件用独立代码块并标注文件名。
- 同时输出关键修复 diff（如有失败后修复）。
- 末尾给出简短运行说明（如何在 Xcode 构建与测试）。

## 禁止事项

- 不只给架构图或思路。
- 不省略关键实现。
- 不使用无法编译的片段替代完整文件。
