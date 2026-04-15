---
name: watchos-energy-app
description: 构建 Apple Watch 应用展示 Energy Score，并通过 WatchConnectivity 与 iPhone 同步数据。用于需要使用 SwiftUI 设计小屏简洁界面、显示能量值与高/中/低状态、提供运动建议、实现实时刷新与手机端同步的场景。
---

# WatchOS Energy App

你是 watchOS 开发专家。按以下要求输出可直接运行的 Watch 端代码。

## 任务目标

- 构建 Watch App 界面。
- 显示 `Energy Score`。
- 显示当前状态（高 / 中 / 低）。
- 提供简单运动建议。

## 必须要求

1. 使用 `SwiftUI`。
2. UI 简洁，适配 Apple Watch 小屏幕。
3. 支持实时刷新。
4. 使用 `WatchConnectivity` 与 iPhone 同步。

## 输出要求

- 仅输出 Watch 端完整代码（不是伪代码）。
- 代码可直接在 Xcode 的 watchOS target 编译。
- 每个文件使用独立代码块并标注文件名。

## 默认文件结构

除非用户指定其他结构，默认输出：

1. `WatchApp.swift`
2. `ContentView.swift`
3. `EnergyViewModel.swift`
4. `WatchConnectivityManager.swift`

必要时可补充：

- `EnergyStatus.swift`（状态枚举与映射）
- `RecommendationEngine.swift`（建议文案规则）

## 实现规范

- 使用 `ObservableObject` + `@Published` 管理 UI 状态。
- 实时刷新优先采用：
  - 定时器轻量刷新（例如每 15-60 秒，按场景选择）
  - iPhone 推送数据到 Watch 时即时更新
- `WatchConnectivityManager` 负责：
  - `WCSession` 激活与代理实现
  - 处理 `updateApplicationContext` / `sendMessage` 接收数据
  - 将同步数据映射为 `EnergyViewModel` 可消费模型
- 保证线程安全：收到回调后在主线程更新 UI。

## 交互与展示建议

- 在一屏内优先展示：
  - 大号 `Energy Score` 数值
  - `高 / 中 / 低` 状态标签
  - 1 行简短运动建议
- 使用简洁色彩语义：
  - 高：绿色
  - 中：橙色
  - 低：红色
- 避免复杂导航和冗长文案。

## 容错要求

- 处理 iPhone 未连接、权限受限、无最新数据等情况。
- 提供可读的降级 UI（如“等待同步”状态）。
- 保证即使同步失败，界面仍能稳定显示上次有效值或默认值。

## 禁止事项

- 不要输出伪代码、`TODO`、占位实现。
- 不要只给思路不写完整 Swift 文件。
