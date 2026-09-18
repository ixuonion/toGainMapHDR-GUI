# GainMapHDR for macOS 27

基于 SwiftUI / Observation 的原生图像批处理应用。正式入口沿用已确认的 Studio UI Demo，调用打包的 `toGainMapHDR` CLI；不改动上游 HDR / Gain Map / Metal / HEIC 算法。

## 构建与运行

需要 macOS 27、Xcode 27、Apple Silicon。Package 使用 Swift tools 6.2、Swift 6 语言模式及 complete strict concurrency；本机 Xcode 27 实际提供的编译器是 Swift 6.4。

```sh
bash script/build_and_run.sh --package
open dist/GainMapHDR.app
```

打包默认使用 Release，`--debug` 使用 Debug。首次构建需下载固定版本的 Swift 官方 `swift-subprocess` 1.0.0；传递依赖由 `Package.resolved` 固定。替换 bundle 前请正常退出应用，构建脚本不会强杀正在转换的实例。产物目前使用本机 ad-hoc 签名，未做 Developer ID 公证。

## 使用

- `⌘O` 导入图片，`⇧⌘O` 导入目录；支持 Finder 打开文件及拖放文件/目录。
- `⌘Return` 转换，`⌘.` 取消。取消期间等待底层进程清理完成，再允许开始下一批。
- “源文件夹”保留 Demo 语义：整批输出到第一张输入图片所在目录；也可选择 Pictures 或自定义目录。
- 命名后缀用于避免覆盖。已存在的输出及本批同名目标会报错，不自动替换。
- Advanced 使用与上方配置相同的原生 Form 行；滑块不显示刻度点。进度按实际处理图片数统计，动效遵循减少动态效果、对比度及应用活跃状态。
- PQ 输出始终显示并传入 10-bit；单色 Gain Map 只可用于 ISO。所有其他图像参数按 CLI 源码契约传递。

## 实现

`StudioView → ConversionStore (@MainActor / @Observable) → ConversionScheduler (actor) → BackendProcessService (Sendable value) → 官方 Subprocess → 原版 CLI`

- 有界结构化 task group 按完成情况补充任务，不为 500 张图片预先创建 500 个活跃转换任务。
- 官方 Subprocess 管理 `posix_spawn`、异步管道和回收；独立进程会话，取消先 SIGTERM，1 秒后 SIGKILL。任务返回即完成清理。
- `ConversionEventBuffer` actor 合并任务状态、限制日志到 200 条 / 64 KiB。UI 最多每 100 ms 接收一次更新，没有逐行 MainActor Task。
- `FileAccessService` actor 扫描目录、读取尺寸、检查文件权限；`ThumbnailService` actor 按选择懒加载，1200 px 下采样，最多缓存 6 张。安全作用域按导入会话持有，清空和退出时释放。
- 每张图片在目标目录下的唯一临时目录转换，验证完整 HEIC 后独占发布；失败/取消清理临时输出。上游二进制与 metallib 原样保留。
- 关闭应用会等待 import task、conversion task 和 subprocess 结束。采用原生单窗口场景。

## 验证

普通单元与生命周期测试（需在正常 macOS 会话运行，HEVC 编码服务在受限沙箱中不可用）：

```sh
bash script/verify.sh
```

上游真实图片与参数回归：

```sh
git clone https://github.com/chemharuka/toGainMapHDR.git /tmp/toGainMapHDR-reference
GAINMAP_INTEGRATION=1 GAINMAP_SAMPLES=/tmp/toGainMapHDR-reference/sample \
  bash script/verify.sh --filter ReferenceIntegrationTests
```

批处理对照：

```sh
GAINMAP_BENCHMARK=1 GAINMAP_SAMPLES=/tmp/toGainMapHDR-reference/sample \
GAINMAP_BATCH_COUNT=100 GAINMAP_BENCHMARK_REPEATS=2 \
GAINMAP_BENCHMARK_REPORT=/tmp/gainmap-benchmark.json \
  bash script/verify.sh --filter BatchBenchmark
```

性能夹具保留重构前的 Process 后端，仅在测试 target 编译；它不进入正式应用。测量范围是旧后端与新调度链的实际吞吐，不能代替多机型性能测试。完整结果及验证边界见 [验证报告](docs/validation/REPORT.md)。

## 上游

- GUI: <https://github.com/ixuonion/toGainMapHDR-GUI>
- Reference CLI: <https://github.com/chemharuka/toGainMapHDR>
- 已检查源码 commit: `2a11df48188bb4449264133d11268149dc8f83bc`
- 打包 CLI SHA-256: `c75c563d11a2568847e10fa7d62da534891818546a00700f90641c61dc5737b8`

上游许可证位于 `Sources/GainMapHDRApp/Resources/backend/LICENSE-toGainMapHDR`，随应用一同分发。
