# 上游核心变更日志

来源仓库：https://github.com/chemharuka/toGainMapHDR
同步提交：`9bc3ed2`
同步日期：2026-05-08

## 新增功能

- 新增 `-R <value>` 参数：限制 tone mapping 使用的最大 headroom，默认值为 `6.0`，同时限制 Apple Gain Map 的 headroom。
- 新增 `-b <base_image>` 参数：允许指定基础 SDR 图像并输出 RGB Gain Map。
- 新增 `-t <text>` 参数：允许在输出文件名后追加自定义后缀。
- 新增 RGB Gain Map 内核与资源：`RGBGainMapFilter.swift`、`RGBGainMapKernel.ci.metal`、`RGBGainMapKernel.ci.metallib`。
- 新增 ISO Gain Map 的 ARGB half-size 输出路径：单独使用 `-H` 可生成 ARGB8 编码的 Adaptive Gain Map。
- 新增 Apple HDR metadata 生成逻辑：`Metadata.swift` 提供 `defaultHDRMetadata(GainMapMax:GainMapMin:)`。

## API 与命令行改动

- `-H` 参数语义更新为 gain map subsample factor，目前仅支持 `1` 或 `2`。
- `-d` 色深继续支持 `8` 和 `10`，但 PQ 强制使用 10-bit，JPEG 输出仍为 8-bit。
- `-c` 色彩空间支持更多别名：`srgb`、`709`、`rec709`、`p3`、`displayp3`、`rec2020`、`2100` 等。
- 输出格式互斥规则更明确：`-p`、`-h`、`-s`、`-g`、`-b`、`-m` 同一时间只能使用一种导出模式。
- JPEG 不支持 PQ 或 HLG transfer function，命令行会直接报错。

## 性能与兼容性优化

- Apple Gain Map half-size 输出在子采样前会裁剪奇数宽高，避免 `-H 2` 处理失败。
- `-R` 与实际图像 headroom 联动，降低过度 headroom 导致的高光裁切风险。
- 默认 ISO Gain Map 使用 RGB gain map 写入路径，兼容 HEIC/JPEG gain map 输出。
- 保留 `GainMapKernel.ci.metallib` 与新增 `RGBGainMapKernel.ci.metallib`，避免运行时动态编译 Metal kernel。

## GUI 项目集成映射

- GUI 新增“最大 Headroom”控件，对应上游 `-R`。
- GUI 将 Apple Gain Map 的缩放选项限制为“完整尺寸/半尺寸”，对应 `-H 1` 与 `-H 2`。
- GUI 运行时依赖检查现在同时校验 `toGainMapHDR`、`GainMapKernel.ci.metallib`、`RGBGainMapKernel.ci.metallib`。
- GUI 内嵌上游源码到 `Vendor/toGainMapHDR`，用于审计、后续合并和离线追踪。
