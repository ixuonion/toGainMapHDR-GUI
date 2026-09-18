# 上游实现审阅与保持不变的边界

审阅版本：`chemharuka/toGainMapHDR@2a11df48188bb4449264133d11268149dc8f83bc`。已阅读 `main.swift`、两个 CustomFilter Swift 类及对应 `.ci.metal`、`Resource/Metadata.swift`，并核对打包 bin 与当前上游 bin 的 SHA-256 一致。

## 实际调用契约

- 每次进程接受一个输入和一个输出目录。CLI 没有批处理会话协议，也没有可靠的单图百分比输出。
- 图像通过 Core Image `.expandToHDR` 载入。GUI 不解码、重采样或重新编码转换输入；ImageIO 仅用于读取尺寸和预览。
- `-q` 是 0…1 的质量，GUI 的 1…100 转成两位小数；`-r`、`-R` 保持 Demo 的一位小数精度，以 POSIX locale 格式化。
- `-H` 是布尔开关，不接受 `2` 这样的参数。奇数尺寸裁剪属于上游原有行为，GUI 不自行调整尺寸。
- `-m` 与 Apple、PQ、HLG、SDR 输出模式互斥。GUI 在其他模式禁用并不传递单色选项。
- PQ 分支始终写 10-bit；GUI 显示实际位深并传 `-d 10`。HLG 保留用户显式选定的位深。
- 输出命名为输入 stem + 选定后缀 + `.heic`，保持 Demo 的“整批输出到第一张图片目录”规则。
- 上游可能因 `try!` 写出错误而异常终止；某些分支未检查 `CGImageDestinationFinalize`。GUI 因此需要输出目录预检、退出状态诊断及 HEIC 完整性检查。

## 没有改变的内容

没有修改 HDR / Gain Map / tone mapping 算法、Metal kernel、色彩空间计算、位深实现、图像 metadata 或 HEIC 写出逻辑。没有增加会改变输出的预处理、重新编码或持久化 worker 协议。

唯一影响 CLI 路径参数的变化是输出到目标目录下的唯一 staging 目录；完成后独占发布原始输出文件，不经过再次编码。已经存在的目标不会被覆盖。临时目录与最终目标位于同一个文件系统，使用 `RENAME_EXCL` 独占重命名；不支持此操作时尝试 hard link，两者均不支持则明确报输出错误。

## 对比方法

- 直接参考：冻结的旧 `Process` runner 调用同一上游 CLI，直接写到 reference 目录。
- 新实现：完整 Scheduler → Subprocess → CLI → staging 验证 → 发布。
- 比较整个 HEIC 的 SHA-256，同时比较解码主图、位深、颜色空间、ImageIO properties、Gain Map 描述和序列化 XMP。
- `CGImageMetadata` 是 CF 对象，不能通过包含它的 NSDictionary 对象身份比较语义；测试改用序列化 XMP。
- 曾尝试额外把结果通过新的 CIContext 重渲染为浮点缓冲区，但相同编码文件也出现重渲染 hash 差异；该二次渲染不是 reference 输出，最终采用更直接且严格的编码文件与解码主图比较。没有为通过测试而改动转换算法。

## 真实 32-bit TIF 的非确定性

用户提供的 Linear Rec. 2020 TIF 在单色 Gain Map 等配置下，直接 CLI 连续运行也观察到不同 HEIC bitstream。一次保存的实例中，直接输出为 6,208,268 字节，第二次直接输出与新调度输出均为 6,208,231 字节，后两者整文件一致；差异涉及 mdat，不能简单归因于时间戳。

回归测试先做直接一次精确比较；若不一致，最多追加三次独立直接 CLI 转换，仍要求 GUI 输出与至少一份独立参考整文件字节一致，且元数据检查通过。没有使用像素误差容差，也没有调整算法或重新编码。此检查能证实本次 GUI 输出是上游实际产生的结果，不能承诺上游每次运行都生成同一个 hash。
