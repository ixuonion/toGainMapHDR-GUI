# Photos Library 验收

## 设计边界

沿用现有 Studio 三栏、Form、队列和底栏；仅增加目的地选项、就地说明、状态文案及现有按钮标题。
保存服务使用 `.addOnly`，每个文件一个 `performChanges`，通过 `.photo` 文件资源导入，
设置 `originalFilename`，`shouldMoveFile = false`。导入期间由调用方持有原文件，
系统回调后才清理。Photos 自身生成的预览或同步行为不影响应用提交的是原始编码字节。

依据：[文件资源创建](https://developer.apple.com/documentation/photos/phassetcreationrequest/addresource(with:fileurl:options:))、
[复制或移动资源](https://developer.apple.com/documentation/photos/phassetresourcecreationoptions/shouldmovefile)、
[仅添加权限](https://developer.apple.com/documentation/photos/phaccesslevel/addonly)、
[权限说明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryaddusagedescription)。

## 自动验证

在正常 macOS 环境运行 `bash script/test.sh`。沙箱若禁止系统 HEVC 编码服务，测试图无法生成，
应在允许访问系统编码服务的宿主环境运行。测试替身不会向真实图库添加照片。
测试比较传入图库保存服务的整个 HEIC 文件字节；真实 Photos 内部存储需要下述人工步骤验证。

## 真实图库验收（需用户操作权限弹窗）

1. 运行 `bash script/build_and_run.sh --package` 并启动 `dist/GainMapHDR.app`。
2. 选择照片图库，转换一张测试图片。首次弹窗应只要求添加照片，并使用当前系统语言。
   拒绝后应显示权限引导；文件夹输出仍可正常使用。授权后重新转换。
3. 用相同输入和参数另存到文件夹，在 Photos 中对新照片执行「导出未修改的原片」。
   比较两份 HEIC 的 SHA-256，以及 ImageIO 的色彩空间、EXIF、XMP、Apple/ISO Gain Map 辅助数据。
   选择已包含 HDR/Gain Map 及元数据的样本分别验证各输出模式。
4. 批量选择不同目录中的同名图片，检查逐张成功状态。对磁盘空间不足、图库不可用等错误
   检查失败详情和部分成功计数；不要重新导入已经成功的图片。
5. 在转换期间和「正在保存到照片图库」期间分别取消：不应继续启动后续任务；
   已提交保存等待完成后显示实际结果；临时目录删除；已经保存的照片保留。
6. 验证系统语言为中文和英文、窄窗口和长错误文案。三栏及原有参数控件位置应保持不变。
7. 开启 iCloud Photos 的机器仅显示图库保存成功，不出现「已上传 iCloud」等同步完成承诺。

本任务自动测试不读取或修改用户真实图库，不包含上述人工验收结果。

## 本次验证记录（2026-09-20）

- Swift 6 / `-strict-concurrency=complete` 构建通过。
- `swift test --disable-sandbox` 通过，Swift Testing 报告 34 tests / 8 suites；需要额外样本及环境开关的原有集成和性能测试仍按默认条件跳过。
- Debug `.app` 打包、`codesign --verify --deep --strict`、主 Info.plist 及两种语言 InfoPlist.strings 校验通过。
- 启动实际应用，检查现有目的地下拉新增「照片图库」、就地多行说明及「转换并保存」按钮；未启动真实图库保存。
- 真实系统授权、图库写入及未修改原片导出比较仍需按上述步骤实测。

- 发布验证：2.1.0（build 210）Release 优化构建通过；Apple Silicon arm64，ZIP 完整性与签名验证通过。
