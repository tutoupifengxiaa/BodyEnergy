---
name: ios-healthkit-dev
description: 开发 iOS 健康类应用，使用 Swift + SwiftUI 并读取 HealthKit 数据（heartRate、activeEnergyBurned、sleepAnalysis）。当用户需要构建可运行的 Xcode 工程、封装 HealthManager、正确申请并使用健康权限、输出完整 Swift 文件（非伪代码）时使用。
---

# iOS HealthKit Dev

按以下要求生成代码与说明，确保项目可直接在 Xcode 中运行。

## 执行目标

- 使用 `Swift` + `SwiftUI` 开发 iOS App。
- 使用 `HealthKit` 读取：
  - 心率（`heartRate`）
  - 活动卡路里（`activeEnergyBurned`）
  - 睡眠（`sleepAnalysis`）
- 将所有 HealthKit 读取逻辑封装在 `HealthManager`。

## 必须遵守

- 使用标准 iOS 项目结构。
- 所有 UI 必须是 SwiftUI。
- 权限申请必须完整且正确，包括：
  - `HKHealthStore.isHealthDataAvailable()` 检查。
  - `requestAuthorization(toShare:read:)` 请求读权限。
  - 说明 `Info.plist` 中的 `NSHealthShareUsageDescription`（以及必要时 `NSHealthUpdateUsageDescription`）。
  - 提醒开启 HealthKit Capability（`*.entitlements`）。
- 禁止输出伪代码，所有示例必须是完整可编译 Swift 文件。

## 默认产出文件

除非用户明确要求其他结构，默认输出以下完整文件：

1. `BodyEnergyApp.swift`
2. `ContentView.swift`
3. `HealthManager.swift`

必要时可增加：

- 数据模型文件（如 `HealthMetric.swift`）
- 格式化工具文件
- 权限与错误处理辅助文件

## 实现规范

- 使用 `ObservableObject` + `@Published` 管理健康数据状态。
- `HealthManager` 负责：
  - 权限申请。
  - 分项查询心率、活动卡路里、睡眠。
  - 将原始样本映射为 UI 可展示的数据。
- 优先使用异步安全写法（如主线程更新状态，避免线程问题）。
- 对查询结果为空、授权失败、设备不支持 HealthKit 等情况提供明确处理。

## 输出格式要求

- 直接给出完整文件内容。
- 每个文件使用独立代码块并标注文件名。
- 不省略 import、类型定义、初始化与关键实现。
- 不使用 `TODO`、`...`、占位函数体等不完整内容。
