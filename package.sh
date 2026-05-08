#!/bin/bash

# HDR Converter 独立打包脚本
# 使用方法: ./package.sh [Debug|Release]

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_NAME="HDRConverter"
CONFIGURATION="${1:-Release}"
BUILD_DIR="$SCRIPT_DIR/build"
ARCHIVE_DIR="$BUILD_DIR/Archive"

echo "========================================="
echo "  HDR Converter 打包脚本"
echo "========================================="
echo ""
echo "配置: $CONFIGURATION"
echo ""

# 1. 清理旧的构建文件
echo "步骤 1: 清理旧的构建文件..."
rm -rf "$BUILD_DIR"

# 2. 自动构建 Xcode 项目
echo ""
echo "步骤 2: 使用 xcodebuild 构建..."
xcodebuild \
    -project "$SCRIPT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$PROJECT_NAME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$ARCHIVE_DIR" \
    build

# 3. 找到构建好的应用
echo ""
echo "步骤 3: 定位应用..."
APP_PATH="$ARCHIVE_DIR/Build/Products/$CONFIGURATION/$PROJECT_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "错误: 找不到构建的应用程序"
    exit 1
fi

echo "找到应用: $APP_PATH"

# 4. 创建输出目录并复制应用
echo ""
echo "步骤 4: 准备输出..."
mkdir -p "$BUILD_DIR/Export"
cp -R "$APP_PATH" "$BUILD_DIR/Export/"
OUTPUT_APP="$BUILD_DIR/Export/$PROJECT_NAME.app"

# 5. 复制必要的资源文件到 MacOS 和 Resources 目录
echo ""
echo "步骤 5: 复制资源文件..."
CONTENTS_MACOS="$OUTPUT_APP/Contents/MacOS"
CONTENTS_RESOURCES="$OUTPUT_APP/Contents/Resources"

if [ -f "$SCRIPT_DIR/toGainMapHDR" ]; then
    cp "$SCRIPT_DIR/toGainMapHDR" "$CONTENTS_MACOS/"
    cp "$SCRIPT_DIR/toGainMapHDR" "$CONTENTS_RESOURCES/"
    chmod +x "$CONTENTS_MACOS/toGainMapHDR"
    chmod +x "$CONTENTS_RESOURCES/toGainMapHDR"
    echo "  ✓ 已复制 toGainMapHDR 到 MacOS 目录"
else
    echo "  ✗ 缺少 toGainMapHDR"
    exit 1
fi

for resource in GainMapKernel.ci.metallib RGBGainMapKernel.ci.metallib; do
    if [ -f "$SCRIPT_DIR/$resource" ]; then
        cp "$SCRIPT_DIR/$resource" "$CONTENTS_MACOS/"
        cp "$SCRIPT_DIR/$resource" "$CONTENTS_RESOURCES/"
        echo "  ✓ 已复制 $resource"
    else
        echo "  ✗ 缺少 $resource"
        exit 1
    fi
done

# 6. 验证应用
echo ""
echo "步骤 6: 验证应用..."
REQUIRED_FILES=(
    "$OUTPUT_APP/Contents/MacOS/toGainMapHDR"
    "$OUTPUT_APP/Contents/MacOS/GainMapKernel.ci.metallib"
    "$OUTPUT_APP/Contents/MacOS/RGBGainMapKernel.ci.metallib"
    "$OUTPUT_APP/Contents/Resources/toGainMapHDR"
    "$OUTPUT_APP/Contents/Resources/GainMapKernel.ci.metallib"
    "$OUTPUT_APP/Contents/Resources/RGBGainMapKernel.ci.metallib"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "  ✗ 缺少: $file"
        exit 1
    fi
done

HELP_OUTPUT=$("$OUTPUT_APP/Contents/MacOS/toGainMapHDR" -help 2>&1 || true)
if [[ "$HELP_OUTPUT" != *"Usage: toGainMapHDR"* ]]; then
    echo "  ✗ toGainMapHDR 无法输出帮助信息"
    exit 1
fi

echo "  ✓ 应用包含所有必要资源"

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

open "$BUILD_DIR/Export"
