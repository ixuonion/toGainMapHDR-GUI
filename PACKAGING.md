# 打包为独立的 macOS 应用程序

本指南将详细说明如何将 HDR Converter 打包为可以独立分发的 macOS 应用程序。

## ✅ 已修复的问题

### 1. Xcode 项目文件引用
- 修复了 mainGroup 配置，源文件现在可以正确找到

### 2. Swift 编译器设置
- 移除了有问题的 `SWIFT_ENFORCE_EXCLUSIVE_ACCESS` 配置
- 移除了有问题的 `SWIFT_STRICT_CONCURRENCY` 配置

### 3. 部署目标
- 从 macOS 15.0 降低到 13.0，兼容性更好

### 4. 沙箱和安全设置
- 禁用了 App Sandbox（ENABLE_SANDBOX = NO）
- 禁用了 Hardened Runtime（ENABLE_HARDENED_RUNTIME = NO）
- 这样应用可以更自由地访问文件系统

### 5. #Preview 宏
- 移除了 ContentView.swift 中的 #Preview 宏，避免命令行构建问题

---

## 🚀 推荐方式：在 Xcode 中构建（最简单 ⭐⭐⭐）

这是最可靠的方式，避免命令行构建的各种问题。

### 步骤

1. **在 Xcode 中打开项目**
   ```bash
   cd /Users/bytedance/HDRConverter
   open HDRConverter.xcodeproj
   ```

2. **选择目标设备**
   - 在 Xcode 顶部工具栏，选择 "My Mac"

3. **构建应用**
   - 菜单栏：Product → Build
   - 或使用快捷键：`Cmd + B`

4. **找到构建好的应用**
   - 在 Xcode 左侧项目导航器中，找到 "Products" 分组
   - 右键点击 "HDRConverter.app"
   - 选择 "Show in Finder"

5. **手动添加资源文件**
   - 右键点击 `HDRConverter.app` → 选择 "显示包内容"
   - 进入 `Contents/MacOS/` 目录
   - 将项目目录下的这两个文件复制进去：
     - `toGainMapHDR`
     - `GainMapKernel.ci.metallib`
   - 设置权限（如果需要）：
     ```bash
     chmod +x /path/to/HDRConverter.app/Contents/MacOS/toGainMapHDR
     ```

6. **（可选）也复制到 Resources 目录**
   - 同样将这两个文件复制到 `Contents/Resources/` 目录作为备用

7. **完成！**
   - 现在您可以直接运行这个应用了
   - 或将其复制到 `/Applications` 目录

---

## 📦 方式二：使用辅助脚本 package.sh

我们提供了一个辅助脚本，它会：
1. 打开 Xcode 项目
2. 让您在 Xcode 中手动构建
3. 等待您完成后，自动复制资源文件
4. 将应用打包到 build/Export 目录

### 使用步骤

```bash
cd /Users/bytedance/HDRConverter
./package.sh
```

然后按照脚本提示操作即可。

---

## 📋 打包后的应用结构

打包好的应用包应该包含以下文件：

```
HDRConverter.app/
└── Contents/
    ├── Info.plist                    # 应用配置
    ├── MacOS/
    │   ├── HDRConverter              # 主程序
    │   ├── toGainMapHDR              # 转换工具（必须）✓
    │   └── GainMapKernel.ci.metallib # Metal 库（必须）✓
    └── Resources/
        ├── toGainMapHDR              # 转换工具（备用）
        └── GainMapKernel.ci.metallib # Metal 库（备用）
```

---

## ✅ 验证打包是否成功

### 1. 检查文件完整性
确保应用包内包含所有必要文件：
```bash
ls -la /path/to/HDRConverter.app/Contents/MacOS/
```
应该能看到：
- HDRConverter
- toGainMapHDR
- GainMapKernel.ci.metallib

### 2. 测试运行
```bash
open /path/to/HDRConverter.app
```

### 3. 功能测试
- 选择一个或多个测试文件
- 尝试转换
- 确认所有功能正常工作

---

## 📤 分发和安装

### 在本机使用
直接运行或复制到应用程序文件夹：
```bash
cp -R /path/to/HDRConverter.app /Applications/
```

### 分发到其他 Mac

#### 方式 A：直接复制
1. 将 `HDRConverter.app` 压缩为 ZIP
2. 发送给其他用户
3. 用户解压后直接使用

#### 方式 B：创建 DMG（更专业）
使用 `create-dmg` 工具创建美观的安装包：

```bash
# 安装工具（如果还没有）
brew install create-dmg

# 创建 DMG
create-dmg \
  --volname "HDR Converter" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "HDRConverter.app" 175 190 \
  --hide-extension "HDRConverter.app" \
  --app-drop-link 425 190 \
  "HDRConverter.dmg" \
  "/path/to/your/app/"
```

---

## ❓ 常见问题解答

### Q: 应用无法启动，提示找不到 toGainMapHDR？
**A:** 确保这两个文件在应用包内的正确位置：
- `Contents/MacOS/toGainMapHDR`
- `Contents/MacOS/GainMapKernel.ci.metallib`

### Q: 权限问题？
**A:** 设置正确的执行权限：
```bash
chmod +x /path/to/HDRConverter.app/Contents/MacOS/toGainMapHDR
```

### Q: Gatekeeper 阻止应用打开？
**A:** 
1. 右键点击应用 → 打开
2. 或在系统偏好设置 → 安全性与隐私中允许

### Q: 想要公开发布应用？
**A:** 建议进行开发者 ID 签名和公证，但这需要 Apple 开发者账号。

---

## 📝 推荐的工作流程

1. **开发时**：直接在 Xcode 中运行和调试
2. **测试和发布时**：使用方式一（Xcode 手动构建）
3. **批量打包时**：使用方式二（package.sh 辅助脚本）

---

## 🎯 总结

**最简单可靠的方式就是：**

1. 在 Xcode 中打开项目
2. 按 Cmd + B 构建
3. 在 Products 中右键 HDRConverter.app → Show in Finder
4. 手动复制 toGainMapHDR 和 GainMapKernel.ci.metallib 到 Contents/MacOS/
5. 完成！

这样就可以得到一个可以独立运行的应用程序了！🎉
