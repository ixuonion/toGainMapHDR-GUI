# toGainMapHDR 线程与核心数性能调研计划

## Summary

本计划已根据最新需求调整为“直接改造 app”，目标是在 `toGainMapHDR-GUI` 中借鉴上游 `heic_hdr.py` 的受限并发调度思路，为批量转换提供可配置的并发选项，并保持运行时自包含、不引入 Python 依赖。

目标产出不再以新增研究文档为主，而是以 app 内功能改造为主：

- 在 GUI 中提供并发配置选项。
- 在 `HDRConverterViewModel.swift` 中把当前串行批处理改造成受限并发多进程调度。
- 保持单文件调用上游 `toGainMapHDR` CLI 的方式不变，只调整“批量调度层”。
- 针对用户常用设备 `M5 Max 18 核 CPU / 32 核 GPU` 设计更合适的默认并发策略。

本轮只读调研已确认的核心事实：

- 上游 Swift CLI `toGainMapHDR/main.swift` 未暴露线程数参数，也未直接使用 `DispatchQueue`、`OperationQueue`、`Thread`、`pthread`、`ProcessInfo.activeProcessorCount` 等线程/核心数控制 API；单文件内部主要依赖 `CoreImage`、`CIContext`、`CIFilter`、`ImageIO` 和 Metal/Core Image 内部调度。
- 上游批处理脚本 `bin/heic_hdr.py` 使用 `ThreadPoolExecutor(max_workers=8)` 并在 README 中注明“默认 8 threads，按芯片性能核心调整”，但该值是硬编码的批量进程并发数，不是 Swift CLI 内部线程池。
- 上游 README 的性能相关内容主要是输出格式、质量、文件体积、PSNR 与半尺寸 gain map，不是针对不同 Mac 核心数的自动优化策略。
- 上游 issue 显示 Intel Mac 与 Apple Silicon 存在兼容性差异，例如 Intel/macOS 15 上的大 AVIF 解码问题与 10-bit gain map 写出路径差异；维护者曾尝试基于 CPU 架构切换 HEIF 写出 API，后续回滚并表示主要支持 Apple Silicon。这是平台兼容性策略，不是核心数/线程数性能调度策略。
- 本项目 GUI 当前在 `HDRConverter/HDRConverterViewModel.swift` 中按输入文件顺序逐个启动 `Process` 调用内嵌 `toGainMapHDR`，没有批量并发、线程池、资源监控或核心数配置 UI。

## Current State Analysis

### 上游仓库观察点

- `README.md`
  - 明确系统要求为 macOS 26.0+，Apple Silicon 完整测试，Intel Mac 部分功能不可用。
  - `heic_hdr.py` 章节提到默认 8 线程，并建议根据芯片性能核心调整。
  - 输出质量表覆盖不同格式、质量参数和半尺寸 gain map 的文件体积/PSNR，但不包含吞吐、CPU/GPU 利用率、功耗、核心数缩放曲线。
  - Known Issue 提到 Intel Mac 上大 AVIF 解码路径和 10-bit gain map 导出问题。
- `toGainMapHDR/main.swift`
  - 全局 `let ctx = CIContext()`。
  - 处理路径为读取 `CIImage`、计算 headroom、生成 SDR/gain map、调用 `writeHEIFRepresentation`、`writeHEIF10Representation` 或 `writeJPEGRepresentation`。
  - 自定义 gain map 计算由 `GainMapFilter`、`RGBGainMapFilter` 和 `.metallib` 驱动。
  - 没有线程数参数、队列宽度参数或按硬件核心数分支。
- `bin/heic_hdr.py`
  - 使用 Python `ThreadPoolExecutor` 启动多个 `toGainMapHDR` 子进程。
  - `max_threads = 8` 为唯一直接核心/线程配置。
  - 未根据 `os.cpu_count()`、性能核心数、内存、输入尺寸或系统负载自动调整。
- issue 讨论
  - `#6` 记录 Intel 2019 MacBook Pro、60MP AVIF、大图宽度超过 8192 像素时的解码问题，并指出 Apple Silicon 使用较新解码器可能不复现。
  - `#7`、`#8` 记录 Intel/macOS 15 上 10-bit gain map 写出路径差异，讨论 `writeHEIFRepresentation(format: .RGB10)` 与 `writeHEIF10Representation` 的兼容性。
  - `#8` 评论中提到曾尝试按 CPU 架构切换写出路径，但最终回滚；维护者表示难以维护 Intel Mac，决定主要支持 Apple Silicon。

### 本项目观察点

- `HDRConverter/HDRConverterViewModel.swift`
  - `convertFiles()` 使用 `for` 循环顺序处理 `inputFilePaths`。
  - `convertSingleFile(_:)` 每个文件启动一个 `Process`，执行本地 `toGainMapHDR`。
  - 当前进度按文件数量计算，预计剩余时间按已完成文件平均耗时估算。
  - `cancel()` 只终止当前单个 `Process`，没有并发子进程集合管理。
- `HDRConverter/ContentView.swift`
  - 当前 UI 包含输出格式、文件格式、质量、色彩空间、位深、SDR 映射比、最大 Headroom、Gain Map 缩放、单色 Gain Map。
  - 没有“性能/并发/功耗”设置区。
- 项目约束
  - 运行时必须自包含，不应依赖外部 CLI。
  - `.metallib` 必须打包到 app 资源。
  - 需要兼容 Xcode 14+，GUI 遵循 macOS HIG。

## Proposed Changes

### 专项结论：是否直接套用 Python 批处理方案

结论：

- 可以借鉴上游 Python 批处理的“多文件并发启动多个 `toGainMapHDR` 子进程”这一思路。
- 不建议把 `bin/heic_hdr.py` 作为本项目运行时实现直接套入 GUI。
- 推荐做法是用 Swift 在 `HDRConverterViewModel.swift` 内重写同等调度逻辑，而不是引入 Python 解释器或额外脚本依赖。

原因分析：

- `heic_hdr.py` 的核心价值只有一层：`ThreadPoolExecutor(max_workers=8)` 驱动多个 CLI 子进程并发处理 TIFF 文件。
- 这个脚本没有 GUI 所需的能力：
  - 没有与 SwiftUI 状态绑定的逐文件进度模型。
  - 没有正在运行任务集合管理。
  - 没有“取消全部任务后回收已产出文件”的交互闭环。
  - 没有针对本项目现有多输入格式、输出格式和日志面板的 UI 集成。
- 直接引入 Python 方案与本项目约束冲突：
  - 当前打包文档 `docs/PACKAGING.md` 只声明 app 内嵌 `toGainMapHDR` 与 `.metallib`，没有 Python runtime。
  - 项目硬约束要求运行时自包含；若依赖系统 Python 或额外打包 Python.framework，会显著提高体积、签名、分发和维护复杂度。
  - 当前 `tests/runtime_checks.sh` 也只验证 CLI 与 Metal 资源，不包含 Python 依赖链。
- 从功能上看，上游 Python 方案并没有“线程池内共享图像处理上下文”的优势；它只是并发启动多个独立进程。这个模式在 Swift 中同样可以实现，而且更适合与 GUI、日志、取消、资源监控结合。

决策：

- 短期实现采用“Swift 版 heic_hdr.py 思路”：
  - 保持上游 CLI `toGainMapHDR` 不变。
  - GUI 侧按设定并发度同时启动多个 `Process`。
  - 用 Swift Concurrency 或受限任务队列代替 Python `ThreadPoolExecutor`。
- 不采用“直接调用 Python 脚本”的方案，除非未来产品目标改变，明确接受捆绑 Python 运行时和额外维护成本。
- 若后续希望进一步减少进程开销，中期方向应是把 upstream 逻辑模块化到 Swift 工程内部，而不是在 Python 层继续叠一层调度。

### 实施改造：GUI 并发选项

修改文件：`HDRConverter/ContentView.swift`

改动内容：

- 在当前“高级设置”区域下方新增“批量性能”设置区。
- 提供以下控件：
  - `并发模式`：`自动（推荐）`、`手动`。
  - `性能偏好`：仅在自动模式可见，选项为 `节能`、`均衡`、`极速`。
  - `并发任务数`：仅在手动模式可见，使用 `Stepper`，范围 `1...8`。
  - `当前生效并发`：只读说明文本，展示最终实际并发值。
  - `硬件摘要`：展示 `processorCount`、`activeProcessorCount`，用于帮助用户理解默认值。
- 文案要求：
  - 明确说明并发的是“同时处理的文件数”，不是上游 CLI 的内部线程数。
  - 对 `极速` 给出风险提示：更高功耗、更高内存压力、可能出现收益递减。
  - 对 Intel 设备显示更保守的帮助说明。

设计决策：

- 不直接暴露“线程池”术语，避免和上游单文件内部调度混淆。
- 优先暴露“并发处理文件数”这一用户可理解概念。

### 实施改造：ViewModel 数据模型

修改文件：`HDRConverter/HDRConverterViewModel.swift`

改动内容：

- 新增枚举：
  - `BatchConcurrencyMode { auto, manual }`
  - `PerformancePreference { efficient, balanced, maxPerformance }`
- 新增状态字段：
  - `@Published var batchConcurrencyMode: BatchConcurrencyMode = .auto`
  - `@Published var performancePreference: PerformancePreference = .balanced`
  - `@Published var manualConcurrentJobs: Int = 4`
  - `@Published private(set) var effectiveConcurrentJobs: Int = 1`
  - `@Published private(set) var hardwareSummary: String`
  - `@Published private(set) var queueStatusMessage: String`
- 新增运行时字段：
  - `private var runningTasks: [UUID: Process] = [:]`
  - `private let processInfo = ProcessInfo.processInfo`
- 新增派生逻辑：
  - `recommendedConcurrentJobs(for fileCount: Int) -> Int`
  - `updateEffectiveConcurrentJobs()`
  - `isAppleSilicon` 判断。

默认值决策：

- 面向用户常用硬件 `M5 Max 18C CPU / 32C GPU`，自动模式默认按 `均衡` 给出 `4` 并发。
- `M5 Max` 上：
  - `节能` -> 2
  - `均衡` -> 4
  - `极速` -> 6
- 对其他 Apple Silicon：
  - `节能` -> 1~2
  - `均衡` -> `min(max(2, activeProcessorCount / 4), 4)`
  - `极速` -> `min(max(3, activeProcessorCount / 3), 6)`
- 对 Intel：
  - `节能` -> 1
  - `均衡` -> 1
  - `极速` -> 2
- 最终生效值始终取 `min(推荐值或手动值, inputFilePaths.count)`，避免文件数不足时出现虚高并发。

说明：

- 这里的默认值故意低于上游 Python 的固定 `8`，因为 GUI 场景下还要兼顾日志、取消、交互体验，以及多个 HEIC 编码任务对 GPU/内存带宽的竞争。

### 实施改造：批量调度逻辑

修改文件：`HDRConverter/HDRConverterViewModel.swift`

改动内容：

- 重写 `convertFiles()`，将当前串行 `for` 循环改为“受限并发调度器”。
- 目标行为等价于上游 `heic_hdr.py` 的：
  - 创建一个待处理文件队列。
  - 同时只启动 `N` 个 `Process`。
  - 任一文件完成后，立即补位启动下一个文件。
- 技术实现：
  - 使用 Swift Concurrency 的 `withTaskGroup`。
  - 用一个轻量级 `actor` 或等效同步方案管理共享队列索引、完成计数、运行中进程表。
  - 每个 worker 循环拉取下一个文件并调用 `convertSingleFile`。
- `convertSingleFile(_:)` 调整为支持：
  - 注册/反注册 `Process` 到 `runningTasks`。
  - 为每个文件返回结构化结果：输入路径、输出路径、耗时、成功/失败、日志片段。
- 进度与日志：
  - 进度按“已完成文件数 / 总文件数”更新。
  - `currentFile` 改为展示最近启动或最近完成的文件。
  - 新增 `queueStatusMessage`，显示“运行中 X / 并发上限 N / 剩余 Y”。

### 实施改造：取消与失败处理

修改文件：`HDRConverter/HDRConverterViewModel.swift`

改动内容：

- `cancel()` 从“终止单个 `currentTask`”改为“终止全部运行中的 `Process`”。
- 取消后：
  - 停止补位调度。
  - 等待已发出的 `terminationHandler` 回收状态。
  - 维持现有“是否删除已转换文件”的交互。
- 失败处理：
  - 单个文件失败不应拖垮整个批次，除非是用户取消。
  - 总结果仍分为：全部成功、部分成功、全部失败、用户取消。
- 线程安全：
  - 所有 UI 发布属性更新统一回到 `MainActor`。

### 实施改造：项目结构策略

修改文件：

- `HDRConverter/ContentView.swift`
- `HDRConverter/HDRConverterViewModel.swift`

不新增新源文件，原因：

- 当前 Xcode 工程 `HDRConverter.xcodeproj/project.pbxproj` 仅登记了 `HDRConverterApp.swift`、`ContentView.swift`、`HDRConverterViewModel.swift` 三个 Swift 源文件。
- 为保持改动聚焦、避免在本轮还需要修改工程文件，优先把新增类型和调度逻辑内聚到 `HDRConverterViewModel.swift`。

### 实施改造：验证范围

代码实现后验证：

- 构建验证：
  - `xcodebuild -project HDRConverter.xcodeproj -scheme HDRConverter -configuration Debug build`
- 运行时验证：
  - `tests/runtime_checks.sh`
- 手动场景验证：
  - 1 个文件时，自动/手动都应生效为 1。
  - 4 个文件时，`M5 Max` 下自动均衡应显示并使用 4 并发。
  - 8 个以上文件时，手动 6 并发应稳定运行。
  - 处理中点击取消，应终止所有运行中任务。
  - 部分文件失败时，应保留成功文件并给出部分成功提示。
  - 日志区应能看到多文件并发处理而非只显示串行单文件状态。

## Assumptions & Decisions

- 不把上游 `bin/heic_hdr.py` 作为运行时依赖；它只作为设计参考，因为本项目要求自包含且当前 GUI 已内嵌 CLI。
- 可以复用上游 Python 方案的“受限并发多进程”模型，但实现层必须改写为 Swift，以满足 app 自包含、签名分发、UI 交互和取消控制要求。
- 不建议短期修改上游 `toGainMapHDR/main.swift` 的单文件内部线程调度；Core Image/Metal 已有内部调度，强行并行滤镜链可能增加复杂度和不稳定性。
- 本轮实施范围锁定为“多文件并发转换”，即 GUI 同时启动有限数量的 `toGainMapHDR` 子进程。
- 自动模式必须保守；针对用户常用 `M5 Max`，默认均衡值为 4，并允许极速提升到 6，手动上限为 8。
- 不把总 CPU 核心数等同于最佳并发数；图像转换可能受 GPU、内存带宽、ImageIO 编码器和系统 HDR API 限制。
- Intel Mac 以兼容性优先，默认并发不高于 2。
- 本轮不新增 Python 运行时、不改打包结构、不修改上游 vendored 核心源码。

## Verification Steps

实现完成后执行以下验证：

- 构建通过，无新增 Swift 编译错误。
- `tests/runtime_checks.sh` 继续通过，确保未破坏现有自包含运行时检查。
- 手动验证自动/手动并发切换时，命令预览保持不变，说明并发是 GUI 调度层行为而不是 CLI 参数变化。
- 手动验证 1、2、4、6 并发时：
  - UI 不冻结。
  - 进度持续更新。
  - 日志顺序允许交错但语义清晰。
  - 取消能终止全部子进程。
  - 部分失败时最终提示正确。

## Execution Order After Approval

1. 修改 `HDRConverter/HDRConverterViewModel.swift`，加入并发配置状态、硬件探测、推荐值逻辑和受限并发调度器。
2. 修改 `HDRConverter/ContentView.swift`，加入批量性能设置 UI 和生效并发展示。
3. 处理取消、日志、进度与部分失败逻辑，确保支持多进程并发。
4. 运行构建与运行时检查，验证 `M5 Max` 场景下默认均衡 4 并发行为。
