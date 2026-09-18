# macOS 27 原生应用重构验证

验证环境：macOS 27.0（26A428）、Xcode 27.0（27A266a）、Apple Swift 6.4、Apple M5 Max / 18 逻辑核心 / 36 GiB RAM。Package 使用 tools 6.2，Swift 6 语言模式与 complete strict concurrency。

## 界面与架构

正式入口为原 Demo 的 Studio 布局，保留三栏、统一 72 pt 顶部与 44 pt 底部、Advanced Form 行和进度动效；去掉旧界面切换与模拟进度窗口。增加真实导入、目录扫描、URL 拖放、Finder 打开事件、参数映射、任务状态、取消、错误和应用退出清理。

`StudioView → @MainActor @Observable ConversionStore → ConversionScheduler actor → BackendProcessService → Swift Subprocess 1.0.0 → 原版 CLI`

应用源码无自定义 `@unchecked Sendable`、NSLock、Task.detached、Process 或 Pipe。仅 AppKit 原生面板回调桥接需要 continuation 和一次取消的 MainActor hop。冻结的旧 Process 实现只存在于测试夹具。

后台有界调度；状态按 ID 汇总，日志限制为 200 条 / 64 KiB，每 100 ms drain 一次。扫描、元数据、缩略图、CLI 及文件发布均不在 MainActor。缩略图优先使用内嵌预览，缺失时下采样至 1200 px，缓存最多 6 张。

输出先写入同文件系统 staging 目录，检查完整 HEIC 后独占发布。已有输出不覆盖，批内同名目标明确报错；取消与错误清理 staging。取消后在进程退出、管道和 task group 收尾前不允许重启。正常退出应用会取消并等待转换与导入。

## 用户 TIF 性能测量

输入为用户 `/Users/xuhao/Desktop/test` 的 25 张 TIF，共约 8.8 GiB，32-bit / RGB / Linear Rec. 2020。尺寸为 3072×4608、4547×6820、4672×7008，最大 32,741,376 像素。

使用原始 TIF 只读输入，所有输出写独立临时目录。每个并发级别测两轮；第二轮反转并发顺序和旧/新运行顺序。未清空系统文件缓存，结果包含真实文件缓存、Metal/HEVC 与系统负载波动。旧基线是冻结的原 Process 后端及相同有限 worker 调用方式；不包含旧 SwiftUI 渲染开销。新值包含预检、调度、staging、验证和发布。

| 设置并发 | 旧后端平均秒数 | 新调度平均秒数 | 新实际 worker |
|---|---:|---:|---:|
| 1 | 52.429 | 46.920 | 1 |
| 2 | 27.037 | 29.775 | 2 |
| 4 | 19.558 | 19.798 | 4 |
| 8 | 18.732 | 18.309 | 6（内存上限） |

原默认最多 4 workers；新 Auto 在此机器/素材上选择 6，平均耗时从 19.558 s 到 18.309 s，减少约 6.4%，吞吐增加约 6.8%。这不是所有配置都提速的结论：同为 4 workers 的均值差约 1.2%，2 workers 在该测量中回退约 10.1%；原因未独立归因，不宣称单纯更换 subprocess 就会加速。

Auto 策略：以实测搜索上界 8 为硬上限，每 worker 预算 `max(2 GiB, 最大像素数 × 96 bytes)`，整批 worker 预算不超过物理内存一半，再按输入数限制。36 GiB + 本组 TIF 得到 6；8 进程旧后端没有超过新 6 进程的平均吞吐。策略不按 CPU 核数直接开满，也不是跨所有机型已验证的最优值。

每秒采样的转换进程总 RSS 观测峰值：新 6 worker 约 14.84 GiB，旧 8 worker 约 16.57 GiB；采样会漏掉短峰值，也不等于完整 GPU 内存账本。完整原始数据：

- [25 张 TIF，两轮交错测量](benchmark-tif.json)
- [TIF 进程 RSS 采样](tif-resource-samples.json)
- [此前 12 张上游 HEIC 样本](benchmark.json)
- [此前 100 张上游 HEIC 样本](benchmark-100.json)

## 输出一致性

上游转换代码和资源未修改。源 CLI SHA-256 为 `c75c563d11a2568847e10fa7d62da534891818546a00700f90641c61dc5737b8`，与审阅版本的上游 bin 一致。

八组参数覆盖 ISO、Apple、PQ、HLG、SDR、单色 Gain Map、半尺寸和自定义质量/P3/10-bit/ratio/headroom。最终 TIF 参数回归中八组全部与第一次独立直接 CLI 的 HEIC 整文件字节一致，元数据和主图检查通过。

此前诊断发现上游自身在少数配置下可能产生不同 bitstream：同一输入与参数，连续两次直接 CLI 输出已不同，而新调度输出与第二次直接结果精确相同。因此测试在首个 hash 不一致时最多追加三次独立直接运行，仍要求精确匹配某一份真实参考，不接受像素容差。不能承诺上游跨运行始终生成同一 hash。源码契约和诊断细节见 [UPSTREAM-CONTRACT.md](UPSTREAM-CONTRACT.md)。

## 自动测试

已验证：参数契约、数值/Auto 边界、UTF-8 跨块与最后一行、stdout/stderr 洪流、日志上限、错误分类、SIGTERM 无效后强制回收、启动前取消、50 次进程 FD 数量稳定、目录去重、500 项模拟后端队列、取消后禁止抢跑/允许完成清理后重启、空输出拒绝、目标碰撞、连续文件打开事件、独占发布竞争，以及真实 TIF 批处理与取消。

硬件编码相关测试需在正常 macOS 会话执行；受限工具沙箱会使 ImageIO/HEVC 编码失败，这不是应用内的沙箱配置。应用当前没有启用 App Sandbox；安全作用域管理用于明确的文件访问生命周期，尚未做 App Store 沙箱分发验证。

### 实际负载与并发安全

- 用户 TIF 的 100 张 APFS 副本完成真实转换，并交替请求缩略图：总测试约 73.276 s，MainActor 的 10 ms 定时探测共 3500 次，最大唤醒间隔约 62.283 ms。该指标是应用状态层响应探测，不等同于 SwiftUI 渲染 FPS。
- 15 个后端/文件安全/原子发布测试在 Thread Sanitizer 下通过，未报告 data race；运行约 8.508 s。
- 完整 TIF 回归实际执行 20 个测试通过；另外 2 个性能/压力测试按环境开关单独执行，未在普通回归中混跑。

## 最终 GUI 复验（2026-09-18）

解锁并恢复窗口捕获后，使用实际 Release 应用完成以下操作：

- 从原生文件夹面板导入用户 25 张 TIF；画面确认源路径、缩略图、自定义输出路径正确刷新。
- 展开 Advanced，检查与上方 Form 的行间隔、分隔线、滑块无刻度点、三栏头尾对齐；运行期间打开日志、切换源图片，界面正常响应。
- 通过工具栏完成全部 25 张转换，显示“转换完成 100%”。逐个通过 ImageIO 完整性、主图解码及 ISO Gain Map 存在性检查。
- 再次通过 ⌘Return 启动相同批次，逐项显示“输出已存在”的明确错误；25 个原输出 SHA-256 均未变化。
- 换到空输出目录，实际点击取消；全部任务标记取消，控件恢复可用，后端进程数为 0，目录无文件和隐藏 staging。
- 取消后再次启动，使用 ⌘. 取消成功；再次启动后在 6 个任务运行中按 ⌘Q，GUI 和 CLI 全部退出，输出目录无残留。重新打开应用正常。
- ⌘O 打开图片面板后 Escape 取消，导入状态正确恢复。原生模态面板打开时 ⌘Q 未触发退出；关闭面板后正常退出，未发生进程挂起。

测试输出位于 `/tmp/gainmap-ui-final-20260918/complete`。本轮未发现需追加修改的功能问题。此前 ScreenCaptureKit -3811 导致的 GUI 复验阻塞已解除；最后的输出路径显示修正已通过画面验证。

## 验证边界

- Release 应用已成功构建，应用包通过 `codesign --verify --deep --strict`；部署版本为 macOS 27.0，二进制架构为 arm64。
- 按用户最新要求，兼容性验收限定为 macOS 27，不将多机型性能验证列为待交付项。性能数字仍仅代表本机和上述样本。
- 500 项测试使用可控模拟后端，验证队列和状态；不能据此声称已经转换 500 张真实 TIF。
- 上游自身的非确定性保留，没有在 GUI 内修改核心算法去消除差异。
- 缺少 Developer ID 签名、公证及多文件系统发布验证；当前交付为本机可运行构建。
- 正常 Cancel / Quit 清理已实现；系统强制杀死 GUI 或断电无法保证删除当时的 staging 目录。
