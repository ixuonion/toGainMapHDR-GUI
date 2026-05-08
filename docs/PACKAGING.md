# 打包配置说明

## 环境要求

- Xcode 14 或更高版本。
- macOS 运行时需要支持上游 `toGainMapHDR` 使用的 Core Image HDR API；上游 README 建议 macOS 26.0+。
- 命令行工具需可用：`xcodebuild`、`shasum`。

## 自动打包

```bash
./package.sh Release
```

输出位置：

```text
build/Export/HDRConverter.app
```

## 打包内容

应用包内会包含以下运行时依赖：

- `Contents/MacOS/toGainMapHDR`
- `Contents/MacOS/GainMapKernel.ci.metallib`
- `Contents/MacOS/RGBGainMapKernel.ci.metallib`
- `Contents/Resources/toGainMapHDR`
- `Contents/Resources/GainMapKernel.ci.metallib`
- `Contents/Resources/RGBGainMapKernel.ci.metallib`

## 验证命令

```bash
./tests/runtime_checks.sh
./package.sh Release
open build/Export/HDRConverter.app
```

`package.sh` 会自动执行 `toGainMapHDR -help`，确认 CLI 可启动。
