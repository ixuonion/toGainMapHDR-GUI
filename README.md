# HDR Converter - macOS GUI Application

基于 [toGainMapHDR](https://github.com/chemharuka/toGainMapHDR) 项目的 macOS GUI 应用程序，提供直观的图形界面来转换 HDR 图片为 Gain Map HDR 格式。

## 功能特性

- **直观的图形界面**：无需使用命令行即可操作
- **批量转换**：支持同时选择和转换多个文件
- **多种输出格式支持**：
  - ISO Gain Map HDR（默认）
  - Apple Gain Map HDR
  - PQ HDR
  - HLG HDR
  - SDR
- **灵活的参数配置**：
  - 图像质量调节
  - 色彩空间选择（sRGB/P3/Rec.2020）
  - 位深度设置（8-bit/10-bit）
  - SDR 映射比例调整
  - Gain Map 缩放（Apple Gain Map 格式）
  - 单色 Gain Map 选项（ISO Gain Map 格式）
- **支持多种输入格式**：TIFF、PNG、HEIC、AVIF、JPEG、JXL、EXR、HDR 等
- **输出格式选择**：HEIC 或 JPEG
- **命令行预览**：实时查看当前配置生成的命令行
- **进度显示**：
  - 实时进度条
  - 当前处理文件显示
  - 预计剩余时间
  - 详细日志查看
- **取消功能**：支持中途取消转换，并询问是否删除已转换文件

## 系统要求

- macOS 15.0+
- Apple Silicon 或 Intel Mac（部分功能在 Intel 上可能受限）

## 如何使用

### 1. 在 Xcode 中打开项目

```bash
open HDRConverter.xcodeproj
```

### 2. 构建并运行

1. 在 Xcode 中选择目标设备（My Mac）
2. 点击运行按钮（▶️）或使用快捷键 `Cmd + R`
3. 应用程序将自动启动

### 3. 使用应用程序

#### 批量选择文件
1. 点击"添加文件"按钮选择一个或多个 HDR 图片
2. 可以继续添加更多文件，或点击单个文件旁的×按钮删除
3. 点击"清空"按钮可清空所有已选文件
4. 选择输出目录（默认与第一个输入文件同目录）

#### 配置参数
1. 在"命令预览"区域查看当前配置生成的命令行
2. 选择输出格式
3. 选择文件格式（HEIC/JPEG）
4. 调整图像质量
5. 在高级设置中配置更多参数

#### 开始转换
1. 点击"转换"按钮开始转换过程
2. 在弹出的进度窗口中查看：
   - 当前处理的文件名
   - 进度条和百分比
   - 预计剩余时间
3. 勾选"显示日志"可查看详细转换日志
4. 点击"取消"按钮可终止转换

#### 转换完成
- 全部成功：显示"全部转换成功"消息
- 部分成功：显示成功/失败数量
- 取消转换：会询问是否删除已转换的文件

## 项目结构

```
HDRConverter/
├── HDRConverter/
│   ├── HDRConverterApp.swift     # 应用程序入口
│   ├── ContentView.swift          # 主界面视图
│   ├── HDRConverterViewModel.swift # 业务逻辑和数据模型
│   └── Assets.xcassets/          # 资源文件
├── HDRConverter.xcodeproj/       # Xcode 项目文件
├── toGainMapHDR                  # 原始可执行文件
├── GainMapKernel.ci.metallib     # Metal 内核库
└── README.md                      # 本说明文件
```

## 关于 toGainMapHDR

本 GUI 应用程序基于原始的 toGainMapHDR 命令行工具开发，该工具使用 Metal API 进行高性能的 HDR 图片处理。

更多信息请参考 [toGainMapHDR 项目](https://github.com/chemharuka/toGainMapHDR)。

## 注意事项

1. **可执行文件路径**：应用程序会自动在以下位置查找 toGainMapHDR 可执行文件：
   - `/Users/bytedance/toGainMapHDR/bin/toGainMapHDR`
   - 应用程序包内的 Contents/MacOS/ 目录
   - 应用程序根目录

2. **沙盒权限**：默认情况下应用程序启用了 App Sandbox，您可能需要在 Xcode 中根据需要调整权限设置。

3. **金属库**：确保 `GainMapKernel.ci.metallib` 文件与应用程序在同一目录下，或正确放置在应用程序包内。

## 许可证

本项目继承自 toGainMapHDR 的 MIT 许可证。
