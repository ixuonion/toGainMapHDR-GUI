# macOS HIG 对照记录

参考文档：

- https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/
- https://developer.apple.com/design/human-interface-guidelines/foundations
- https://developer.apple.com/design/human-interface-guidelines/patterns
- https://developer.apple.com/design/human-interface-guidelines/components
- https://developer.apple.com/design/human-interface-guidelines/inputs

## Foundations

- 使用 SwiftUI 系统颜色和 Material 背景，避免硬编码浅色/深色背景。
- 保留 `.foregroundStyle(.secondary/.tertiary)`，让文本层级自动适配系统外观。
- 使用最小窗口尺寸与滚动容器，支持大屏和小屏窗口缩放。
- 用 `.monospacedDigit()` 优化进度、百分比和参数数值的排版稳定性。

## Patterns

- 主界面以单窗口生产力工具形式呈现，减少不必要的模态层级。
- 转换进度仍使用 sheet，符合用户需要持续关注当前任务的场景。
- 命令预览与运行时状态提供可复制文本，便于用户诊断和复现。
- 打包脚本保证 app bundle 自包含，避免用户安装额外 CLI。

## Components

- 主操作“转换”使用 prominent button，次要操作使用 bordered/plain 样式。
- 输出格式和参数使用 Picker、Slider、Toggle 等系统控件，保留原生可访问性。
- Apple Gain Map 子采样从自由 Slider 改为 segmented Picker，避免无效值。
- 运行时错误使用系统警告图标和语义颜色，而不是仅依赖文字。

## Inputs

- 支持鼠标/触控板点击、悬停 tooltip、文本复制和文件选择面板。
- 文件选择使用 `NSOpenPanel`，遵循 macOS 文件访问模式。
- 转换取消仍可通过按钮执行，后续建议补充菜单命令与键盘快捷键。

## 深浅色模式

- UI 主要依赖 SwiftUI 动态颜色、Material 和系统控件，自动响应系统深色/浅色模式。
- 新增状态卡片继续使用 `.thinMaterial` 与语义色，避免固定背景造成对比度问题。

## 响应式布局

- 主窗口设置最小尺寸，内容在垂直方向通过 ScrollView 适配。
- 文件列表在大量文件时切换摘要视图，避免小屏幕下长列表挤压核心操作。
- 参数区域使用 `maxWidth: .infinity` 伸缩，保留宽屏可读性。
