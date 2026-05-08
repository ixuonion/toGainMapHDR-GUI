# 代码合并说明

## 合并范围

- 上游源码完整复制到 `Vendor/toGainMapHDR`。
- 上游最新 CLI 二进制替换项目根目录 `toGainMapHDR`。
- 上游运行时 Metal 资源复制到项目根目录：`GainMapKernel.ci.metallib`、`RGBGainMapKernel.ci.metallib`。
- 上游许可证保存为 `LICENSE.upstream`。

## GUI 改动

- `HDRConverterViewModel.swift` 新增 `RuntimeStatus`，应用启动时检查独立运行所需资源。
- `HDRConverterViewModel.swift` 新增 `maxHeadroom`，构建命令时输出 `-R <value>`。
- `HDRConverterViewModel.swift` 去除本机绝对路径 fallback，避免打包后依赖开发环境。
- `ContentView.swift` 新增运行时依赖状态区，缺失资源时直接展示用户可读错误。
- `ContentView.swift` 新增最大 Headroom 控件，并将 Apple Gain Map 缩放改为分段选择。

## Xcode 工程改动

- `HDRConverter.xcodeproj/project.pbxproj` 新增 `RGBGainMapKernel.ci.metallib` 资源引用。
- 应用目标继续将 `toGainMapHDR` 与 Metal 资源复制到 app bundle 的 `Contents/Resources`。
- `package.sh` 会额外复制这些运行时资源到 `Contents/MacOS`，满足上游 `Bundle.main.url(forResource:)` 查找行为。

## 风险与后续建议

- 上游 README 声明核心工具要求 macOS 26.0+，当前 GUI 工程仍保留较低 deployment target 以满足 Xcode 14+ 编译要求；实际转换功能取决于运行系统是否支持核心工具所用 Core Image API。
- 当前使用上游发布的 CLI 二进制作为运行时核心，没有把命令行 target 合并进 GUI 的同一个 Xcode project target graph；`Vendor/toGainMapHDR` 已保留源码，后续可进一步改为 workspace/aggregate target 自动构建 CLI。
