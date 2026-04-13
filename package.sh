#!/bin/bash

# HDR Converter 打包脚本
# 使用方法: ./package.sh

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_NAME="HDRConverter"
CONFIGURATION="Debug"
BUILD_DIR="$SCRIPT_DIR/build"

echo "========================================="
echo "  HDR Converter 打包脚本"
echo "========================================="
echo ""
echo "注意：推荐在 Xcode 中直接构建，这个脚本用于自动化打包"
echo ""

# 1. 清理旧的构建文件
echo "步骤 1: 清理旧的构建文件..."
rm -rf "$BUILD_DIR"

# 2. 打开 Xcode 项目让用户手动构建
echo ""
echo "步骤 2: 正在打开 Xcode 项目..."
echo ""
echo "请在 Xcode 中："
echo "  1. 选择目标设备: My Mac"
echo "  2. 选择 Product -> Build (Cmd + B)"
echo "  3. 等待构建完成"
echo "  4. 在 Xcode 左侧 Products 分组中右键 HDRConverter.app"
echo "  5. 选择 'Show in Finder'"
echo "  6. 然后按任意键继续..."
echo ""

open "$SCRIPT_DIR/$PROJECT_NAME.xcodeproj"

read -p "构建完成后按任意键继续..." -n1 -s

# 3. 找到构建好的应用
echo ""
echo "步骤 3: 定位应用..."
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/"$PROJECT_NAME"-*/Build/Products/"$CONFIGURATION" -name "$PROJECT_NAME.app" -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "未找到 Debug 构建，尝试查找 Release..."
    APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/"$PROJECT_NAME"-*/Build/Products/Release -name "$PROJECT_NAME.app" -type d 2>/dev/null | head -1)
fi

if [ -z "$APP_PATH" ]; then
    echo "错误: 找不到构建的应用程序"
    echo "请确保已在 Xcode 中完成构建"
    exit 1
fi

echo "找到应用: $APP_PATH"

# 4. 创建输出目录并复制应用
echo ""
echo "步骤 4: 准备输出..."
mkdir -p "$BUILD_DIR/Export"
cp -R "$APP_PATH" "$BUILD_DIR/Export/"
OUTPUT_APP="$BUILD_DIR/Export/$PROJECT_NAME.app"

# 5. 复制必要的资源文件
echo ""
echo "步骤 5: 复制资源文件..."
CONTENTS_MACOS="$OUTPUT_APP/Contents/MacOS"
CONTENTS_RESOURCES="$OUTPUT_APP/Contents/Resources"

# 复制到 MacOS 目录
if [ -f "$SCRIPT_DIR/toGainMapHDR" ]; then
    cp "$SCRIPT_DIR/toGainMapHDR" "$CONTENTS_MACOS/"
    chmod +x "$CONTENTS_MACOS/toGainMapHDR"
    echo "  ✓ 已复制 toGainMapHDR 到 MacOS 目录"
fi

if [ -f "$SCRIPT_DIR/GainMapKernel.ci.metallib" ]; then
    cp "$SCRIPT_DIR/GainMapKernel.ci.metallib" "$CONTENTS_MACOS/"
    echo "  ✓ 已复制 GainMapKernel.ci.metallib 到 MacOS 目录"
fi

# 也复制到 Resources 目录作为备用
if [ -f "$SCRIPT_DIR/toGainMapHDR" ]; then
    cp "$SCRIPT_DIR/toGainMapHDR" "$CONTENTS_RESOURCES/"
    chmod +x "$CONTENTS_RESOURCES/toGainMapHDR"
fi

if [ -f "$SCRIPT_DIR/GainMapKernel.ci.metallib" ]; then
    cp "$SCRIPT_DIR/GainMapKernel.ci.metallib" "$CONTENTS_RESOURCES/"
fi

# 6. 验证应用
echo ""
echo "步骤 6: 验证应用..."
if [ -f "$OUTPUT_APP/Contents/MacOS/toGainMapHDR" ] && [ -f "$OUTPUT_APP/Contents/MacOS/GainMapKernel.ci.metallib" ]; then
    echo "  ✓ 应用包含所有必要资源"
else
    echo "  ⚠ 警告: 部分资源可能缺失"
fi

echo ""
echo "========================================="
echo "  打包成功！"
echo "========================================="
echo ""
echo "应用位置: $OUTPUT_APP"
echo ""
echo "您可以:"
echo "  1. 直接运行: open $OUTPUT_APP"
echo "  2. 复制到应用程序: cp -R $OUTPUT_APP /Applications/"
echo "  3. 在 Finder 中打开: open $BUILD_DIR/Export"
echo ""

# 打开输出目录
open "$BUILD_DIR/Export"
